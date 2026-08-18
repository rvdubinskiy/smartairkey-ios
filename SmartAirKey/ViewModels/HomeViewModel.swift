import Foundation
import Combine
import UIKit

/// Drives the main screen: the seamless-access toggle, the door list, manual
/// opens, success feedback and actionable errors. Speaks only in domain terms.
@MainActor
final class HomeViewModel: ObservableObject {

    // Seamless access (reqs. 1–5, UI 1/3)
    @Published var isSeamlessOn: Bool
    @Published private(set) var isSeamlessBusy = false

    // Doors (reqs. 8/9, UI 2/3)
    @Published private(set) var doors: [Door] = []
    @Published private(set) var isLoadingKeys = false

    // Feedback
    @Published var activeError: AccessError?
    @Published var successDoorName: String?

    // Bluetooth (req. 6)
    @Published private(set) var bluetooth: BluetoothAvailability = .unknown

    // Location — needs "Always" so doors open with the app closed (req. 7)
    @Published private(set) var location: LocationAvailability = .unknown

    /// The user asked to turn seamless access on, but not every access was
    /// granted yet. We keep the switch off and finish enabling automatically
    /// once Bluetooth *and* "Always" location are both granted.
    @Published private(set) var pendingEnable = false

    private let access: SeamlessAccessService
    private let bluetoothAuth: BluetoothAuthorizing
    private let locationAuth: LocationAuthorizing
    private let analytics: AnalyticsLogging
    private let keyProvider: KeyProviding
    private let config: AppConfig
    /// Whether a valid user token is present. Keys are only fetched after the
    /// resident has authorized (phone sign-in → per-user token).
    private let hasValidToken: () -> Bool
    /// Called when the backend rejects our token (user not found / token
    /// invalid) so the app can sign the user out and return to sign-in.
    private let onAuthenticationLost: () -> Void

    private var cancellables = Set<AnyCancellable>()
    private var lastOpenRequestedDoorID: String?
    /// Whether keys have ever loaded successfully this session. Once they have,
    /// a failed *refresh* degrades gracefully (keep the loaded doors, no blocking
    /// alert) instead of nagging on every pull-to-refresh.
    private var hasLoadedKeysOnce = false

    init(access: SeamlessAccessService,
         bluetoothAuth: BluetoothAuthorizing,
         locationAuth: LocationAuthorizing,
         analytics: AnalyticsLogging,
         keyProvider: KeyProviding,
         config: AppConfig,
         hasValidToken: @escaping () -> Bool = { true },
         onAuthenticationLost: @escaping () -> Void = {}) {
        self.access = access
        self.bluetoothAuth = bluetoothAuth
        self.locationAuth = locationAuth
        self.analytics = analytics
        self.keyProvider = keyProvider
        self.config = config
        self.hasValidToken = hasValidToken
        self.onAuthenticationLost = onAuthenticationLost
        self.isSeamlessOn = access.isSeamlessAccessEnabled
        bind()
    }

    convenience init(environment: AppEnvironment) {
        self.init(access: environment.access,
                  bluetoothAuth: environment.bluetooth,
                  locationAuth: environment.location,
                  analytics: environment.analytics,
                  keyProvider: environment.keyProvider,
                  config: environment.config,
                  hasValidToken: { [session = environment.session] in
                      (session.accessToken?.isEmpty == false)
                  },
                  onAuthenticationLost: { [weak environment] in
                      environment?.signOutCleanup()
                  })
    }

    // MARK: Lifecycle

    /// Called when the home screen appears. Idempotent.
    func onAppear() {
        // Ask for Bluetooth and location up front. The location request is
        // staged (When-In-Use first, then upgraded to "Always") so doors keep
        // opening even after the app was closed or evicted from memory (req. 7),
        // and background monitoring resumes automatically once "Always" is
        // granted.
        bluetoothAuth.requestAuthorization()
        locationAuth.requestAlwaysAuthorization()
        // If an access was revoked or downgraded while we were away, seamless
        // access can no longer work — switch it off so the toggle can't stay on
        // with a missing access. The user must re-grant everything to turn it
        // back on. (Re-checked again when authorization callbacks land.)
        enforceSeamlessAccessRequirements()
        access.start()
        Task { await refreshKeys() }
    }

    private func bind() {
        // The SDK polls every controller continuously, so `doors` can fire many
        // times a second with 20+ locks. Drop no-op updates and coalesce bursts
        // to at most a few per second so the main thread (and the whole UI,
        // including the sign-out/sign-in screens) stays responsive.
        access.doors
            .removeDuplicates()
            .throttle(for: .milliseconds(300), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] doors in self?.doors = doors }
            .store(in: &cancellables)

        access.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)

        bluetoothAuth.availabilityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] availability in self?.handleBluetooth(availability) }
            .store(in: &cancellables)

        locationAuth.availabilityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] availability in self?.handleLocation(availability) }
            .store(in: &cancellables)
    }

    // MARK: Keys (reqs. 1, 2, 10)

    func refreshKeys() async {
        // Must be authorized first: keys are fetched only with a valid user
        // token (obtained via phone sign-in → GetUserToken).
        guard hasValidToken() else {
            AppLog.backend.error("Skipping key fetch: not authorized (no user token)")
            return
        }
        isLoadingKeys = true
        defer { isLoadingKeys = false }
        do {
            var data = try await keyProvider.fetchDigitalKeys()

            // Accept any keys the access-manager granted (pending
            // `incomingKeysRequests`) so they become usable, then refetch to
            // pick up the now-approved keys/cryptoKeys. This is **best-effort**:
            // if approval fails we still load whatever keys are already usable,
            // rather than failing the whole refresh (a single un-approvable
            // pending request must not blank out the door list). Auth failures
            // are rethrown so we can sign out.
            if config.autoApproveIncomingKeys,
               let approver = keyProvider as? KeyRequestApproving {
                do {
                    let approved = try await approver.approvePendingKeyRequests(in: data)
                    if approved > 0 {
                        AppLog.backend.info("Auto-approved \(approved, privacy: .public) key request(s); refetching")
                        data = try await keyProvider.fetchDigitalKeys()
                    }
                } catch let error as BackendError where error.isAuthFailure {
                    throw error
                } catch {
                    AppLog.backend.error("Auto-approve failed, continuing with current keys: \(String(describing: error), privacy: .public)")
                }
            }

            let summary = try access.loadKeys(serverJSON: data)
            hasLoadedKeysOnce = true
            // A successful load clears a stale refresh error (but never an
            // unrelated alert, e.g. a door-open failure).
            if activeError == .keysRefreshFailed { activeError = nil }
            AppLog.backend.info("Keys loaded active=\(summary.active, privacy: .public) dropped=\(summary.dropped, privacy: .public)")
        } catch let error as BackendError where error.isAuthFailure {
            // The token is no longer valid (user not found / revoked): don't
            // leave the user stuck on the home screen — sign out so they can
            // authorize again.
            AppLog.backend.error("Authentication lost — signing out")
            analytics.log(.error(domain: "auth", reason: "unauthorized"))
            onAuthenticationLost()
        } catch {
            AppLog.backend.error("Key refresh failed: \(String(describing: error), privacy: .public)")
            analytics.log(.error(domain: "keys", reason: "\(error)"))
            // Don't block the user with an alert if we already have usable keys:
            // the loaded doors keep working, and a transient refresh hiccup
            // shouldn't nag on every pull-to-refresh. Surface the hard error only
            // when nothing has loaded yet (a genuine empty first load).
            if !hasLoadedKeysOnce {
                activeError = .keysRefreshFailed
            }
        }
    }

    // MARK: Seamless toggle (reqs. 3, 4, 5)

    /// Every access seamless background opening needs: Bluetooth ready *and*
    /// "Always" location. Read live from the authorizers so the decision never
    /// races the published mirrors.
    var allAccessGranted: Bool {
        bluetoothAuth.availability == .ready && locationAuth.availability == .ready
    }

    /// Handles the toggle. Enabling is **blocked** until every access is granted:
    /// we prompt for what's missing, keep the switch off, and finish enabling
    /// automatically once the user grants everything.
    func setSeamless(_ enabled: Bool) {
        guard enabled else {
            pendingEnable = false
            applySeamless(false)
            return
        }

        guard allAccessGranted else {
            // Can't turn it on yet — remember the intent, request what's
            // missing, and leave the switch off until access is granted.
            pendingEnable = true
            requestRequiredAccess()
            surfaceAccessErrorIfNeeded()
            return
        }

        pendingEnable = false
        applySeamless(true)
    }

    /// Actually turns seamless access on/off once the decision is made.
    private func applySeamless(_ enabled: Bool) {
        isSeamlessOn = enabled
        isSeamlessBusy = true
        access.setSeamlessAccess(enabled: enabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isSeamlessBusy = false
        }
    }

    private func requestRequiredAccess() {
        bluetoothAuth.requestAuthorization()
        locationAuth.requestAlwaysAuthorization()
    }

    /// Surfaces the first missing-access error, if any. When access is still
    /// undetermined there's no error yet — the system prompts are what appear.
    private func surfaceAccessErrorIfNeeded() {
        if let error = bluetooth.error ?? location.error {
            activeError = error
        }
    }

    var seamlessStatusText: String {
        if isSeamlessBusy {
            return isSeamlessOn
                ? L10n.string("seamless.state.turning_on")
                : L10n.string("seamless.state.turning_off")
        }
        if pendingEnable {
            return L10n.string("seamless.state.needs_access")
        }
        return isSeamlessOn
            ? L10n.string("seamless.state.on")
            : L10n.string("seamless.state.off")
    }

    var seamlessSubtitle: String {
        if pendingEnable {
            return L10n.string("seamless.subtitle.needs_access")
        }
        return isSeamlessOn
            ? L10n.string("seamless.subtitle.on")
            : L10n.string("seamless.subtitle.off")
    }

    // MARK: Manual open (req. 9)

    func open(_ door: Door) {
        guard door.status.canOpen else { return }
        lastOpenRequestedDoorID = door.id
        analytics.log(.doorOpenRequested(doorID: door.id))
        Haptics.tap()
        access.open(doorID: door.id)
    }

    // MARK: Events

    private func handle(_ event: AccessEvent) {
        switch event {
        case let .doorOpened(doorID):
            analytics.log(.doorOpenSucceeded(doorID: doorID))
            Haptics.success()
            successDoorName = doors.first(where: { $0.id == doorID })?.name ?? L10n.string("open.success")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                self?.successDoorName = nil
            }
        case let .openFailed(doorID):
            analytics.log(.doorOpenFailed(doorID: doorID, reason: "open_failed"))
            Haptics.error()
            activeError = .openFailed(doorID: doorID)
        case let .failure(error):
            analytics.log(.error(domain: "access", reason: error.analyticsReason))
            activeError = error
        }
    }

    private func handleBluetooth(_ availability: BluetoothAvailability) {
        bluetooth = availability
        reactToAccessChange()
    }

    private func handleLocation(_ availability: LocationAvailability) {
        location = availability
        reactToAccessChange()
    }

    /// Reacts when Bluetooth or location authorization changes: finishes a
    /// pending enable once everything is granted; turns the feature *off* if an
    /// access was lost while it was on; otherwise nags (Bluetooth first, then
    /// location) while the user is trying to turn seamless access on.
    private func reactToAccessChange() {
        if pendingEnable, allAccessGranted {
            pendingEnable = false
            activeError = nil
            applySeamless(true)
            return
        }

        if isSeamlessOn {
            // On but an access is now missing → switch off (does nothing while
            // everything is still granted or authorization is unresolved).
            enforceSeamlessAccessRequirements()
        } else if pendingEnable, let error = bluetooth.error ?? location.error {
            activeError = error
        }
    }

    /// Seamless access requires *every* access at all times. If it's currently
    /// on but an access has been revoked or downgraded, switch it off and
    /// surface what to fix — the user must re-grant everything before enabling
    /// it again. Acts only on a definite bad state, never while authorization is
    /// still resolving (`.unknown`), so a valid setup is never turned off by a
    /// transient state.
    private func enforceSeamlessAccessRequirements() {
        guard isSeamlessOn else { return }
        guard let error = bluetooth.error ?? location.error else { return }
        AppLog.access.info("Access lost while seamless was on — disabling")
        applySeamless(false)
        activeError = error
    }

    // MARK: Error actions (UI req. 4)

    func perform(_ action: ErrorAction, for error: AccessError? = nil) {
        switch action {
        case .openSettings:
            openSettings(for: error ?? activeError)
        case .retry:
            let doorID = lastOpenRequestedDoorID
            activeError = nil
            if let doorID, let door = doors.first(where: { $0.id == doorID }) {
                open(door)
            } else {
                Task { await refreshKeys() }
            }
        case .contactSupport:
            if let url = config.supportURL {
                UIApplication.shared.open(url)
            }
        }
        if action != .retry { activeError = nil }
    }

    /// Opens the most relevant Settings screen for the error. When Bluetooth is
    /// *off* we try to deep-link straight to the Bluetooth screen — the on/off
    /// toggle the user actually needs — and fall back to the app's own Settings
    /// page if that can't be opened. A *denied* Bluetooth permission (and every
    /// other error) goes to the app page, where the permission toggles live.
    private func openSettings(for error: AccessError?) {
        let appSettings = URL(string: UIApplication.openSettingsURLString)
        if error == .bluetoothOff, let bluetoothPane = URL(string: "App-Prefs:root=Bluetooth") {
            UIApplication.shared.open(bluetoothPane) { opened in
                if !opened, let appSettings { UIApplication.shared.open(appSettings) }
            }
            return
        }
        if let appSettings { UIApplication.shared.open(appSettings) }
    }
}
