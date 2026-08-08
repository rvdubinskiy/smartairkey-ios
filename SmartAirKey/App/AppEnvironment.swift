import Foundation

/// Runtime configuration. With no `backendBaseURL` the app runs in demo mode
/// (bundled keys + demo sign-in), so it is fully explorable without a server.
struct AppConfig {
    /// Base URL of the SmartAirKey mobile backend, e.g. https://apidev.smartairkey.com
    var backendBaseURL: URL?
    /// Support contact surfaced by the "Contact support" error action.
    var supportURL: URL? = URL(string: "mailto:support@smartairkey.com")

    /// Company SAS token used to exchange a phone number for a per-user token
    /// via `GetUserToken` at sign-in. Required for real phone sign-in; without
    /// it the app falls back to demo sign-in. Supplied via `SAK_COMPANY_TOKEN`.
    ///
    /// There is deliberately no preset user-token shortcut: the app must
    /// authorize by phone first, and only the resulting per-user token is used
    /// to fetch keys.
    var companyToken: String?

    /// When true, keys the access-manager grants (which arrive as pending
    /// `incomingKeysRequests`) are auto-accepted on refresh so they become
    /// usable without a manual approval step. Enabled for live/test runs so
    /// integration can be verified end to end; off in demo mode.
    var autoApproveIncomingKeys: Bool = false

    static let demo = AppConfig(backendBaseURL: nil)

    /// Resolves the runtime config from the launch environment so secrets stay
    /// out of source control. In Xcode: Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸
    /// Arguments ▸ Environment Variables, add:
    ///   • `SAK_BASE_URL`     = https://api.smartairkey.com  (your backend)
    ///   • `SAK_COMPANY_TOKEN`= <company SAS token>          (enables phone sign-in)
    /// With `SAK_BASE_URL` set the app runs against the live backend; the user
    /// then signs in by phone number to obtain a per-user token. No env vars →
    /// demo mode.
    static var resolved: AppConfig {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["SAK_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw) else {
            return .demo
        }
        return AppConfig(backendBaseURL: url,
                         companyToken: env["SAK_COMPANY_TOKEN"],
                         autoApproveIncomingKeys: true)
    }
}

/// Composition root: builds and owns the app's services and wires the SDK seam.
///
/// The real SmartAirKey SDK service is used on device; Simulator/previews use the
/// in-memory mock so the whole UI is exercisable without hardware.
final class AppEnvironment: ObservableObject {

    let config: AppConfig
    let session: SessionStore
    let bluetooth: BluetoothAuthorization
    let location: LocationAuthorization
    let analytics: AnalyticsLogging
    let preferences: SeamlessPreferenceStoring
    let access: SeamlessAccessService
    let auth: Authenticating
    let keyProvider: KeyProviding

    init(config: AppConfig = .demo,
         session: SessionStore = SessionStore(),
         bluetooth: BluetoothAuthorization = BluetoothAuthorization(),
         location: LocationAuthorization = LocationAuthorization(),
         analytics: AnalyticsLogging = OSLogAnalytics(),
         preferences: SeamlessPreferenceStoring = SeamlessPreferenceStore(),
         access: SeamlessAccessService? = nil,
         auth: Authenticating? = nil,
         keyProvider: KeyProviding? = nil) {

        self.config = config
        self.session = session
        self.bluetooth = bluetooth
        self.location = location
        self.analytics = analytics
        self.preferences = preferences
        self.access = access ?? AppEnvironment.makeAccessService(analytics: analytics,
                                                                 preferences: preferences)
        self.auth = auth ?? AppEnvironment.makeAuth(config: config)
        self.keyProvider = keyProvider ?? AppEnvironment.makeKeyProvider(config: config,
                                                                        session: session)
    }

    private static func makeAccessService(analytics: AnalyticsLogging,
                                          preferences: SeamlessPreferenceStoring) -> SeamlessAccessService {
        #if canImport(AirKeySmartDeviceCore) && !targetEnvironment(simulator)
        return AirKeyAccessService(analytics: analytics, preferences: preferences)
        #else
        return MockAccessService(preferences: preferences, analytics: analytics)
        #endif
    }

    private static func makeAuth(config: AppConfig) -> Authenticating {
        if let base = config.backendBaseURL, let company = config.companyToken, !company.isEmpty {
            return SmartAirKeyAuthService(baseURL: base, companyToken: company)
        }
        return DemoAuthService()
    }

    private static func makeKeyProvider(config: AppConfig, session: SessionStore) -> KeyProviding {
        if let base = config.backendBaseURL {
            return SmartAirKeyBackendClient(baseURL: base, tokenProvider: { session.accessToken })
        }
        return BundledKeyProvider()
    }

    /// Removes all on-device secrets and keys (req. 11).
    func signOutCleanup() {
        access.clear()
        preferences.reset()
        session.clear()
        analytics.log(.signedOut)
    }
}
