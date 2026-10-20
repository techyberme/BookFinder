import Foundation
import Security
import ZahoriKit

/// Reader card + password in the iOS Keychain: this device only, never synced to iCloud,
/// readable after the first unlock (so a refresh can run while the phone is locked).
enum CredentialStore {
    private static let service = "es.zahori.lector"
    private static let account = "reader"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> ReaderCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ReaderCredentials.self, from: data)
    }

    @discardableResult
    static func save(_ credentials: ReaderCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
