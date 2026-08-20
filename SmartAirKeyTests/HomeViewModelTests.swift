import XCTest
import Combine
@testable import SmartAirKey

/// Verifies the key rule: seamless access cannot be turned on until **every**
/// access (Bluetooth *and* "Always" location) is granted, and that it finishes
/// enabling automatically once the user grants everything.
@MainActor
final class HomeViewModelTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    /// Lets the main-queue async pipeline (Combine sinks delivered on
    /// `DispatchQueue.main`) drain before asserting.
    private func waitForMainQueue() {
        let settled = expectation(description: "main queue settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2.0)
    }

    private func makeViewModel(
        bluetooth: BluetoothAvailability,
        location: LocationAvailability,
        preferences: InMemoryPreferences = InMemoryPreferences()
    ) -> (HomeViewModel, FakeBluetoothAuth, FakeLocationAuth, MockAccessService) {
        let bt = FakeBluetoothAuth(bluetooth)
        let loc = FakeLocationAuth(location)
        let access = MockAccessService(preferences: preferences, analytics: SpyAnalytics())
        let vm = HomeViewModel(access: access,
                               bluetoothAuth: bt,
                               locationAuth: loc,
                               analytics: SpyAnalytics(),
                               keyProvider: EmptyKeyProvider(),
                               config: .demo)
        return (vm, bt, loc, access)
    }

    /// Bluetooth ready but location only "While Using" → must NOT enable.
    func testEnableBlockedWhenLocationIsOnlyWhenInUse() {
        let (vm, bt, loc, access) = makeViewModel(bluetooth: .ready, location: .whenInUseOnly)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn, "switch must stay off until all access is granted")
        XCTAssertFalse(access.isSeamlessAccessEnabled, "feature must not be enabled")
        XCTAssertTrue(vm.pendingEnable, "the intent to enable should be remembered")
        XCTAssertGreaterThanOrEqual(bt.requestCount, 1, "Bluetooth should be requested")
        XCTAssertGreaterThanOrEqual(loc.requestCount, 1, "location should be requested")
    }

    /// Bluetooth ready but location fully denied → must NOT enable. Only
    /// "Always" location unlocks the feature.
    func testEnableBlockedWhenLocationDenied() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .ready, location: .denied)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// A pending enable must stay blocked if location only reaches "While Using"
    /// — "Always" is mandatory for opening doors while the app is closed.
    func testPendingEnableStaysBlockedWithWhenInUseLocation() {
        let (vm, bt, loc, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)
        bt.set(.ready)
        loc.set(.whenInUseOnly) // upgraded, but not all the way to "Always".

        let settled = expectation(description: "pipeline settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2.0)

        XCTAssertFalse(vm.isSeamlessOn, "When-In-Use is not enough; needs Always")
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// Location "Always" but Bluetooth denied → must NOT enable.
    func testEnableBlockedWhenBluetoothDenied() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .denied, location: .ready)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// Nothing decided yet → blocked, prompts fired, no error surfaced yet.
    func testEnableBlockedWhenAccessUndetermined() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
        XCTAssertNil(vm.activeError, "no error while the system prompts are still pending")
    }

    /// Both Bluetooth ready and location "Always" → enables immediately.
    func testEnableSucceedsWhenAllAccessGranted() {
        let (vm, _, _, access) = makeViewModel(bluetooth: .ready, location: .ready)

        vm.setSeamless(true)

        XCTAssertTrue(vm.isSeamlessOn)
        XCTAssertTrue(access.isSeamlessAccessEnabled)
        XCTAssertFalse(vm.pendingEnable)
    }

    /// After a blocked attempt, granting the remaining access finishes enabling
    /// automatically — the user doesn't have to toggle again.
    func testPendingEnableCompletesOnceAllAccessGranted() {
        let (vm, bt, loc, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)
        XCTAssertTrue(vm.pendingEnable)
        XCTAssertFalse(vm.isSeamlessOn)

        let enabled = expectation(description: "auto-enabled once all access granted")
        vm.$isSeamlessOn
            .filter { $0 }
            .sink { _ in enabled.fulfill() }
            .store(in: &cancellables)

        bt.set(.ready)
        loc.set(.ready)

        wait(for: [enabled], timeout: 2.0)
        XCTAssertTrue(vm.isSeamlessOn)
        XCTAssertTrue(access.isSeamlessAccessEnabled)
        XCTAssertFalse(vm.pendingEnable)
    }

    /// Granting only part of the access must NOT auto-enable.
    func testPendingEnableStaysBlockedWithPartialAccess() {
        let (vm, bt, _, access) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.setSeamless(true)
        bt.set(.ready) // Bluetooth granted, location still undetermined.

        // Give the async pipeline a moment; nothing should flip on.
        let settled = expectation(description: "pipeline settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2.0)

        XCTAssertFalse(vm.isSeamlessOn, "must not enable without location Always")
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertTrue(vm.pendingEnable)
    }

    /// Feature on, then Bluetooth is revoked while running → it must switch OFF
    /// automatically (it can't work without every access).
    func testSeamlessTurnsOffWhenBluetoothRevoked() {
        let prefs = InMemoryPreferences()
        prefs.isSeamlessAccessEnabled = true
        let (vm, bt, _, access) = makeViewModel(bluetooth: .ready, location: .ready, preferences: prefs)
        XCTAssertTrue(vm.isSeamlessOn)

        bt.set(.denied)
        waitForMainQueue()

        XCTAssertFalse(vm.isSeamlessOn, "must switch off when an access is revoked")
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertNotNil(vm.activeError, "the user should be told what to fix")
    }

    /// Feature on, then location is downgraded from "Always" to "While Using" →
    /// must switch OFF ("Always" is mandatory).
    func testSeamlessTurnsOffWhenLocationDowngraded() {
        let prefs = InMemoryPreferences()
        prefs.isSeamlessAccessEnabled = true
        let (vm, _, loc, access) = makeViewModel(bluetooth: .ready, location: .ready, preferences: prefs)
        XCTAssertTrue(vm.isSeamlessOn)

        loc.set(.whenInUseOnly)
        waitForMainQueue()

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
    }

    /// Opening the toggle screen with the feature on but an access already
    /// missing must switch it off (req: check on appear).
    func testOnAppearDisablesSeamlessWhenAccessMissing() {
        let prefs = InMemoryPreferences()
        prefs.isSeamlessAccessEnabled = true
        let (vm, _, _, access) = makeViewModel(bluetooth: .off, location: .ready, preferences: prefs)

        vm.onAppear()
        waitForMainQueue()

        XCTAssertFalse(vm.isSeamlessOn, "must not stay on when an access is missing")
        XCTAssertFalse(access.isSeamlessAccessEnabled)
    }

    /// A valid setup must NOT be turned off when the screen appears.
    func testOnAppearKeepsSeamlessOnWhenAllAccessGranted() {
        let prefs = InMemoryPreferences()
        prefs.isSeamlessAccessEnabled = true
        let (vm, _, _, access) = makeViewModel(bluetooth: .ready, location: .ready, preferences: prefs)

        vm.onAppear()
        waitForMainQueue()

        XCTAssertTrue(vm.isSeamlessOn, "a fully-granted setup stays on")
        XCTAssertTrue(access.isSeamlessAccessEnabled)
    }

    // MARK: Native prompts vs. Settings fallback

    /// Fresh install (all undetermined): enabling fires the native prompts and
    /// shows NO Settings alert — the system modals ask in-app.
    func testNoSettingsAlertWhenUndetermined() {
        let (vm, bt, loc, _) = makeViewModel(bluetooth: .unknown, location: .unknown)
        bt.canPromptForAuthorization = true
        loc.canPromptForAlways = true

        vm.setSeamless(true)

        XCTAssertNil(vm.activeError, "no Settings alert while native prompts can appear")
        XCTAssertGreaterThanOrEqual(bt.requestCount, 1)
        XCTAssertGreaterThanOrEqual(loc.requestCount, 1)
    }

    /// Granted "While Using" but the native "Always" upgrade prompt is still
    /// available → no Settings alert; the native prompt does the asking.
    func testNoSettingsAlertWhileAlwaysPromptAvailable() {
        let (vm, _, loc, _) = makeViewModel(bluetooth: .ready, location: .whenInUseOnly)
        loc.canPromptForAlways = true

        vm.setSeamless(true)

        XCTAssertNil(vm.activeError, "let the native Always prompt appear, not a Settings alert")
        XCTAssertNil(vm.locationSettingsError)
        XCTAssertGreaterThanOrEqual(loc.requestCount, 1)
    }

    /// Once the native "Always" prompt is exhausted (user chose "Keep While
    /// Using"), we DO fall back to the Settings alert.
    func testSettingsAlertWhenAlwaysPromptExhausted() {
        let (vm, _, loc, _) = makeViewModel(bluetooth: .ready, location: .whenInUseOnly)
        loc.canPromptForAlways = false

        vm.setSeamless(true)

        XCTAssertEqual(vm.activeError, .locationWhenInUseOnly)
        XCTAssertEqual(vm.locationSettingsError, .locationWhenInUseOnly)
    }

    /// Denied Bluetooth can't be reprompted by iOS → Settings alert.
    func testSettingsAlertWhenBluetoothDenied() {
        let (vm, _, _, _) = makeViewModel(bluetooth: .denied, location: .ready)

        vm.setSeamless(true)

        XCTAssertEqual(vm.activeError, .bluetoothDenied)
    }

    /// Turning it off is always allowed and clears any pending intent.
    func testDisableAlwaysWorks() {
        let prefs = InMemoryPreferences()
        prefs.isSeamlessAccessEnabled = true
        let (vm, _, _, access) = makeViewModel(bluetooth: .ready, location: .ready, preferences: prefs)
        XCTAssertTrue(vm.isSeamlessOn)

        vm.setSeamless(false)

        XCTAssertFalse(vm.isSeamlessOn)
        XCTAssertFalse(access.isSeamlessAccessEnabled)
        XCTAssertFalse(vm.pendingEnable)
    }

    /// The home screen requests both Bluetooth and location up front (item 1).
    func testOnAppearRequestsBluetoothAndLocation() {
        let (vm, bt, loc, _) = makeViewModel(bluetooth: .unknown, location: .unknown)

        vm.onAppear()

        XCTAssertGreaterThanOrEqual(bt.requestCount, 1)
        XCTAssertGreaterThanOrEqual(loc.requestCount, 1)
    }

    /// A refresh that fails *after* keys already loaded must NOT show a blocking
    /// alert — the loaded doors keep working; only pull-to-refresh feedback ends.
    func testRefreshFailureAfterSuccessDoesNotAlert() async {
        let provider = FlakyKeyProvider() // succeeds once, then fails
        let vm = HomeViewModel(
            access: MockAccessService(preferences: InMemoryPreferences(), analytics: SpyAnalytics()),
            bluetoothAuth: FakeBluetoothAuth(.ready),
            locationAuth: FakeLocationAuth(.ready),
            analytics: SpyAnalytics(),
            keyProvider: provider,
            config: .demo,
            hasValidToken: { true }
        )

        await vm.refreshKeys() // first load succeeds
        XCTAssertNil(vm.activeError)

        await vm.refreshKeys() // now fails
        XCTAssertNil(vm.activeError, "a refresh failure must not nag once keys are loaded")
    }

    /// But a failure on the *first* load (nothing usable yet) still surfaces the
    /// error so the user knows the screen is empty for a reason.
    func testRefreshFailureOnFirstLoadShowsAlert() async {
        let vm = HomeViewModel(
            access: MockAccessService(preferences: InMemoryPreferences(), analytics: SpyAnalytics()),
            bluetoothAuth: FakeBluetoothAuth(.ready),
            locationAuth: FakeLocationAuth(.ready),
            analytics: SpyAnalytics(),
            keyProvider: FailingKeyProvider(),
            config: .demo,
            hasValidToken: { true }
        )

        await vm.refreshKeys()

        XCTAssertEqual(vm.activeError, .keysRefreshFailed)
    }

    /// A failing auto-approve step must not fail the whole refresh: the keys that
    /// are already usable still load, and no blocking alert appears.
    func testAutoApproveFailureStillLoadsKeys() async {
        let provider = ApproveFailingKeyProvider()
        let vm = HomeViewModel(
            access: MockAccessService(preferences: InMemoryPreferences(), analytics: SpyAnalytics()),
            bluetoothAuth: FakeBluetoothAuth(.ready),
            locationAuth: FakeLocationAuth(.ready),
            analytics: SpyAnalytics(),
            keyProvider: provider,
            config: AppConfig(backendBaseURL: URL(string: "https://example.com"),
                              autoApproveIncomingKeys: true),
            hasValidToken: { true }
        )

        await vm.refreshKeys()

        XCTAssertNil(vm.activeError, "an approval hiccup must not blank out the door list")
        XCTAssertGreaterThanOrEqual(provider.fetchCount, 1)
    }

    /// A backend auth failure (user not found / token invalid) signs the user
    /// out instead of leaving them stuck on the home screen.
    func testUnauthorizedResponseSignsOut() async {
        var signedOut = false
        let vm = HomeViewModel(
            access: MockAccessService(preferences: InMemoryPreferences(), analytics: SpyAnalytics()),
            bluetoothAuth: FakeBluetoothAuth(.ready),
            locationAuth: FakeLocationAuth(.ready),
            analytics: SpyAnalytics(),
            keyProvider: UnauthorizedKeyProvider(),
            config: .demo,
            hasValidToken: { true },
            onAuthenticationLost: { signedOut = true }
        )

        await vm.refreshKeys()

        XCTAssertTrue(signedOut, "a 401/unauthorized should force sign-out")
        XCTAssertNil(vm.activeError, "no generic error alert when signing out")
    }
}

// MARK: - Test doubles

final class FakeBluetoothAuth: BluetoothAuthorizing {
    private let subject: CurrentValueSubject<BluetoothAvailability, Never>
    private(set) var requestCount = 0
    var canPromptForAuthorization = false

    init(_ initial: BluetoothAvailability) {
        subject = CurrentValueSubject(initial)
    }

    var availability: BluetoothAvailability { subject.value }
    var availabilityPublisher: AnyPublisher<BluetoothAvailability, Never> {
        subject.eraseToAnyPublisher()
    }
    func requestAuthorization() { requestCount += 1 }
    func set(_ value: BluetoothAvailability) { subject.send(value) }
}

final class FakeLocationAuth: LocationAuthorizing {
    private let subject: CurrentValueSubject<LocationAvailability, Never>
    private(set) var requestCount = 0
    var canPromptForAlways = false

    init(_ initial: LocationAvailability) {
        subject = CurrentValueSubject(initial)
    }

    var availability: LocationAvailability { subject.value }
    var availabilityPublisher: AnyPublisher<LocationAvailability, Never> {
        subject.eraseToAnyPublisher()
    }
    func requestAlwaysAuthorization() { requestCount += 1 }
    func set(_ value: LocationAvailability) { subject.send(value) }
}

final class UnauthorizedKeyProvider: KeyProviding {
    func fetchDigitalKeys() async throws -> Data { throw BackendError.unauthorized }
}

final class EmptyKeyProvider: KeyProviding {
    func fetchDigitalKeys() async throws -> Data { Data("[]".utf8) }
}

/// Succeeds on the first fetch, then fails — models a working session whose
/// later refresh hits a transient backend/network error.
final class FlakyKeyProvider: KeyProviding {
    private var calls = 0
    func fetchDigitalKeys() async throws -> Data {
        calls += 1
        if calls == 1 { return Data("[]".utf8) }
        throw BackendError.badResponse(status: 500)
    }
}

/// Always fails the fetch — models a genuine first-load failure.
final class FailingKeyProvider: KeyProviding {
    func fetchDigitalKeys() async throws -> Data { throw BackendError.badResponse(status: 500) }
}

/// Fetch works, but approving a pending key request fails — the refresh should
/// still load the already-usable keys.
final class ApproveFailingKeyProvider: KeyProviding, KeyRequestApproving {
    private(set) var fetchCount = 0
    func fetchDigitalKeys() async throws -> Data {
        fetchCount += 1
        return Data("[]".utf8)
    }
    func approvePendingKeyRequests(in profileJSON: Data) async throws -> Int {
        throw BackendError.badResponse(status: 500)
    }
}
