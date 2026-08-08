import Foundation
import Combine

/// Holds the signed-in resident's credentials/token, backed by the Keychain.
///
/// The token is the app's proof to the SmartAirKey backend that it may fetch
/// this resident's digital keys. Cleared on sign-out (req. 11).
final class SessionStore: ObservableObject {

    private enum Account {
        static let token = "session.accessToken"
    }

    @Published private(set) var isSignedIn: Bool

    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        self.isSignedIn = keychain.string(for: Account.token) != nil
        AppLog.auth.info("Session restored on launch: signedIn=\(self.isSignedIn ? "true" : "false", privacy: .public)")
    }

    var accessToken: String? {
        keychain.string(for: Account.token)
    }

    /// Persists the token to the Keychain so it survives app restarts. If the
    /// write fails we log it (previously the error was silently swallowed, which
    /// looked like "the token doesn't persist").
    func save(accessToken: String) {
        do {
            try keychain.setString(accessToken, for: Account.token)
            AppLog.auth.info("Access token persisted to Keychain")
        } catch {
            AppLog.auth.error("Failed to persist access token: \(String(describing: error), privacy: .public)")
        }
        isSignedIn = true
    }

    /// Removes all tokens and secrets from the device.
    func clear() {
        keychain.removeAll()
        isSignedIn = false
    }
}
