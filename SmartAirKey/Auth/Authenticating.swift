import Foundation

/// Signs a resident in by phone number and returns their **user** SAS token
/// (`apiKeyId:token`) for use on `/api/mobile`.
///
/// `DemoAuthService` lets the app run without a live server;
/// `SmartAirKeyAuthService` calls the real `GetUserToken` endpoint.
protocol Authenticating {
    func signIn(phoneNumber: String) async throws -> String
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case notConfigured
    case network(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return L10n.string("auth.error.invalid")
        case .notConfigured: return L10n.string("auth.error.not_configured")
        case .network: return L10n.string("error.generic.message")
        }
    }
}

/// Offline/demo sign-in: accepts any plausible phone number and mints a local
/// token. Handy for Simulator and reviewers without backend access.
struct DemoAuthService: Authenticating {
    func signIn(phoneNumber: String) async throws -> String {
        let digits = phoneNumber.filter(\.isNumber)
        guard digits.count >= 10 else { throw AuthError.invalidCredentials }
        // A demo user token in the same apiKeyId:token shape the app expects.
        return "demoKey:" + Data(digits.utf8).base64EncodedString()
    }
}

/// Real sign-in against the SmartAirKey mobile backend. Exchanges the company
/// SAS token for a per-user token via
/// `POST /api/service/company/GetUserToken` (`{"PhoneNumber": ...}`) and
/// returns the assembled `apiKeyId:token`.
///
/// - Important: the company SAS token is a privileged credential (it can mint a
///   token for any subscriber by phone number). Shipping it inside a mobile app
///   is a security risk; in production this exchange belongs on your own server.
///   It's wired here so the integration can be exercised end to end.
struct SmartAirKeyAuthService: Authenticating {

    let baseURL: URL
    let companyToken: String
    let session: URLSession
    var path: String = "/api/service/company/GetUserToken"

    init(baseURL: URL, companyToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.companyToken = companyToken
        self.session = session
    }

    func signIn(phoneNumber: String) async throws -> String {
        let phone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !companyToken.isEmpty else { throw AuthError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue(SmartAirKeyBackendClient.authorizationHeader(for: companyToken),
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.timestamp(), forHTTPHeaderField: "Timestamp")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["PhoneNumber": phone]
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AuthError.network(underlying: URLError(.badServerResponse))
            }
            AppLog.auth.info("GetUserToken status=\(http.statusCode, privacy: .public)")
            guard http.statusCode == 200 else {
                let body = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
                AppLog.auth.error("GetUserToken failed status=\(http.statusCode, privacy: .public) body=\(body, privacy: .public)")
                throw AuthError.invalidCredentials
            }
            let payload = try JSONDecoder().decode(UserTokenResponse.self, from: data)
            return "\(payload.apiKeyId):\(payload.token)"
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.network(underlying: error)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: Date())
    }

    private struct UserTokenResponse: Decodable {
        let apiKeyId: String
        let token: String
    }
}
