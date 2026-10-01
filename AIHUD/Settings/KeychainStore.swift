import Foundation
import Security

enum KeychainStore {
    static let service = "com.duoi.axiom"
    static let chatAccount = "api-key"
    static let visionAccount = "vision-api-key"

    static func chatAccount(for id: UUID) -> String {
        "api-key.\(id.uuidString)"
    }

    static func read(account: String = chatAccount) -> String? {
        if DevCredentials.suppressesKeychain {
            return DevCredentials.secret(account: account)
        }
        if let value = read(account: account, dataProtection: true), !value.isEmpty {
            return value
        }
        return read(account: account, dataProtection: false)
    }

    private static func read(account: String, dataProtection: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String = chatAccount) throws {
        if DevCredentials.suppressesKeychain {
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess {
            return
        }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        insert[kSecAttrSynchronizable as String] = false
        insert[kSecUseDataProtectionKeychain as String] = true
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    static func delete(account: String = chatAccount) {
        if DevCredentials.suppressesKeychain {
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case status(OSStatus)
}
