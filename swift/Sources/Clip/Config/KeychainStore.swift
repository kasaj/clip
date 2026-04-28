import Foundation
import Security

enum KeychainStore {
    private static let service = "com.jz.Clip"

    // MARK: - Provider API (id is now a plain String)

    private static func account(forProviderID id: String) -> String {
        "clip.provider.\(id)"
    }

    static func save(apiKey: String, forProviderID id: String) throws {
        try write(apiKey, account: account(forProviderID: id))
    }
    static func load(forProviderID id: String) throws -> String {
        try read(account: account(forProviderID: id))
    }
    static func hasKey(forProviderID id: String) -> Bool {
        (try? load(forProviderID: id))?.isEmpty == false
    }
    static func delete(forProviderID id: String) {
        remove(account: account(forProviderID: id))
    }

    // MARK: - Private helpers

    private static func write(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query; addQuery[kSecValueData as String] = data
            let s = SecItemAdd(addQuery as CFDictionary, nil)
            guard s == errSecSuccess else { throw KeychainError.saveFailed(s) }
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func read(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError.notFound }
        return key
    }

    private static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound
    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): "Keychain save failed: \(s)"
        case .notFound:          "API klíč nenalezen v Keychain"
        }
    }
}
