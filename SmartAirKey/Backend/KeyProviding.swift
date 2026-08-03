import Foundation

/// Fetches the resident's digital keys from the SmartAirKey backend (req. 1).
///
/// Returns the raw server JSON. Decoding into SDK models happens strictly inside
/// the Access layer, keeping the SDK out of the rest of the app.
protocol KeyProviding {
    func fetchDigitalKeys() async throws -> Data
}

/// Accepts keys the access-manager sent from the control panel. Per the SDK
/// docs a granted key first lands in `incomingKeysRequests` of the profile and
/// only appears in `keys`/`cryptoKeys` once approved — so integration testing
/// needs this step, otherwise no doors show up.
protocol KeyRequestApproving {
    /// Approves every pending incoming key request found in a GetUserProfileV2
    /// payload. Returns how many were approved.
    func approvePendingKeyRequests(in profileJSON: Data) async throws -> Int
}

enum BackendError: LocalizedError {
    case notAuthenticated
    case badResponse(status: Int)
    case emptyData
    case transport(Error)

    var errorDescription: String? {
        L10n.string("error.keys_failed.message")
    }
}

/// Network implementation. Uses the resident's session token to authorize the
/// request, per the SmartAirKey mobile API (SAS-TOKEN + Timestamp headers).
struct SmartAirKeyBackendClient: KeyProviding, KeyRequestApproving {

    let baseURL: URL
    let session: URLSession
    let tokenProvider: () -> String?
    /// Endpoint returning the resident's keys ("route": keys + cryptoKeys).
    /// Per SDK docs the mobile profile action is `GetUserProfileV2`.
    var path: String = "/api/mobile"
    var query: [URLQueryItem] = [URLQueryItem(name: "Action", value: "GetUserProfileV2")]

    init(baseURL: URL,
         session: URLSession = .shared,
         tokenProvider: @escaping () -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func fetchDigitalKeys() async throws -> Data {
        guard let token = tokenProvider() else {
            AppLog.backend.error("Key fetch aborted: no SAS token in session")
            throw BackendError.notAuthenticated
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw BackendError.badResponse(status: -1) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("SAS-TOKEN \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(Self.timestamp(), forHTTPHeaderField: "Timestamp")

        // Diagnostics: URL + a masked token so a wrong/empty token or endpoint
        // is obvious in Console without leaking the secret.
        AppLog.backend.info("Fetching keys url=\(url.absoluteString, privacy: .public) token=\(Self.mask(token), privacy: .public)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                AppLog.backend.error("Keys fetch: non-HTTP response")
                throw BackendError.badResponse(status: -1)
            }
            AppLog.backend.info("Keys response status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data.prefix(600), encoding: .utf8) ?? "<binary>"
                AppLog.backend.error("Keys request failed status=\(http.statusCode, privacy: .public) body=\(body, privacy: .public)")
                throw BackendError.badResponse(status: http.statusCode)
            }
            guard !data.isEmpty else {
                AppLog.backend.error("Keys request returned empty body")
                throw BackendError.emptyData
            }
            return data
        } catch let error as BackendError {
            throw error
        } catch {
            AppLog.backend.error("Keys transport error: \(String(describing: error), privacy: .public)")
            throw BackendError.transport(error)
        }
    }

    /// Masks a token for logs: first/last few chars + length, never the whole
    /// secret. Lets you confirm the right token is present without exposing it.
    private static func mask(_ token: String) -> String {
        guard token.count > 8 else { return "set(len \(token.count))" }
        return "\(token.prefix(4))…\(token.suffix(4)) (len \(token.count))"
    }

    // MARK: Key request approval (KeyRequestApproving)

    func approvePendingKeyRequests(in profileJSON: Data) async throws -> Int {
        let ids = Self.pendingRequestIds(in: profileJSON)
        guard !ids.isEmpty else { return 0 }
        AppLog.backend.info("Approving \(ids.count, privacy: .public) pending key request(s)")
        for id in ids {
            try await approveKeyRequest(id: id)
        }
        return ids.count
    }

    /// Extracts the ids of pending incoming key requests from a GetUserProfileV2
    /// payload. Tolerant: any shape mismatch yields an empty list.
    private static func pendingRequestIds(in data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requests = root["incomingKeysRequests"] as? [[String: Any]] else {
            return []
        }
        return requests.compactMap { $0["id"] as? String }
    }

    private func approveKeyRequest(id: String) async throws {
        guard let token = tokenProvider() else { throw BackendError.notAuthenticated }
        let url = baseURL.appendingPathComponent("/api/mobile/KeyRequestApprove")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("SAS-TOKEN \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.timestamp(), forHTTPHeaderField: "Timestamp")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["Action": "KeyRequestApprove", "RequestId": id]
        )

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            AppLog.backend.error("KeyRequestApprove failed id=\(id, privacy: .public) status=\(code, privacy: .public) body=\(body, privacy: .public)")
            throw BackendError.badResponse(status: code)
        }
        AppLog.backend.info("Approved key request id=\(id, privacy: .public)")
    }

    /// UTC timestamp in the format the SmartAirKey mobile API expects
    /// (ISO-8601 with milliseconds and a literal `Z`), e.g. per SDK docs
    /// `2025-01-23T07:28:57.628Z`.
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: Date())
    }
}

/// Offline/demo provider that serves a bundled `route.sample.json`, so the app
/// is fully explorable without a live backend or granted keys.
struct BundledKeyProvider: KeyProviding {

    var resource = "route.sample"

    func fetchDigitalKeys() async throws -> Data {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw BackendError.emptyData
        }
        return try Data(contentsOf: url)
    }
}
