import Foundation
import Security

/// Minimal Keychain wrapper for storing secrets (access tokens).
///
/// Digital keys and tokens live in the Keychain and are removed on sign-out
/// (req. 11). Items use `kSecAttrAccessibleAfterFirstUnlock` so background BLE
/// work (req. 7) can still read them while the device is locked.
struct KeychainStore {

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.smartairkey.seamless") {
        self.service = service
    }

    func setData(_ data: Data, for account: String) throws {
        // Delete-then-add is the most reliable write: it avoids SecItemUpdate
        // edge cases (e.g. changing accessibility) that could leave the value
        // unpersisted. `AfterFirstUnlock` keeps the token readable across app
        // termination and while locked (background BLE), so it survives a full
        // app restart.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    func removeItem(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Removes every secret this app stored (used on sign-out, req. 11).
    func removeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Convenience string helpers.
    func setString(_ value: String, for account: String) throws {
        try setData(Data(value.utf8), for: account)
    }

    func string(for account: String) -> String? {
        data(for: account).flatMap { String(data: $0, encoding: .utf8) }
    }
}
