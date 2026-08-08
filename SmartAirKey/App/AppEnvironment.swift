import Foundation

/// Runtime configuration. With no `backendBaseURL` the app runs in demo mode
/// (bundled keys + demo sign-in), so it is fully explorable without a server.
struct AppConfig {
    /// Base URL of the SmartAirKey mobile backend, e.g. https://apidev.smartairkey.com
    var backendBaseURL: URL?
    /// Support contact surfaced by the "Contact support" error action.
    var supportURL: URL? = URL(string: "mailto:support@smartairkey.com")

    /// DEV/TEST ONLY: a preset **subscriber** SAS token used to skip the sign-in
    /// screen and exercise the real backend on device. This must be the per-user
    /// `apiKeyId:token` pair (obtained by exchanging the company SAS-TOKEN via
    /// `GET /api/service/company/GetUserToken` — see scripts/get_user_token.sh),
    /// NOT the company SAS-TOKEN itself. It is sent verbatim as
    /// `Authorization: SAS-TOKEN apiKeyId:token` to `/api/mobile`.
    /// Leave `nil` in committed code — supply it via the scheme's
    /// `SAK_SAS_TOKEN` environment variable (safe, not stored in git). It is
    /// seeded into the Keychain on launch and cleared by Sign Out.
    var developerAccessToken: String?

    /// Company SAS token used to exchange a phone number for a per-user token
    /// via `GetUserToken` at sign-in. Required for real phone sign-in; without
    /// it the app falls back to demo sign-in. Supplied via `SAK_COMPANY_TOKEN`.
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
    ///   • `SAK_BASE_URL`  = https://apidev.smartairkey.com  (your backend)
    ///   • `SAK_SAS_TOKEN` = <your SAS token>                (optional)
    /// With `SAK_BASE_URL` set the app runs against the live backend; with a
    /// token too, it skips sign-in and immediately fetches keys. No env vars →
    /// unchanged demo mode.
    static var resolved: AppConfig {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["SAK_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw) else {
            return .demo
        }
        return AppConfig(backendBaseURL: url,
                         developerAccessToken: env["SAK_SAS_TOKEN"],
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
        seedDeveloperTokenIfNeeded()
    }

    /// DEV/TEST: if a preset SAS token is configured, seed it into the session
    /// so the app skips sign-in and fetches keys with it. No-op when absent or
    /// already signed in.
    private func seedDeveloperTokenIfNeeded() {
        guard let token = config.developerAccessToken?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty, !session.isSignedIn else { return }
        session.save(accessToken: token)
        AppLog.auth.info("Seeded preset SAS token into session (test build).")
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
