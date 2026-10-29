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
        do {
            try write(value, account: account, dataProtection: true)
        } catch KeychainError.status(errSecMissingEntitlement) {
            // A build without an application identifier cannot use the data-protection keychain.
            try write(value, account: account, dataProtection: false)
        }
    }

    private static func write(_ value: String, account: String, dataProtection: Bool) throws {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess {
            return
        }
        if update != errSecItemNotFound {
            throw KeychainError.status(update)
        }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        insert[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    static func delete(account: String = chatAccount) {
        for dataProtection in [true, false] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            if dataProtection {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            SecItemDelete(query as CFDictionary)
        }
    }
}

/// Where `EndpointStore` keeps keys. Tests pass an in-memory one so they never touch the real Keychain.
struct SecretStore {
    var read: (_ account: String) -> String?
    var write: (_ value: String, _ account: String) throws -> Void
    var delete: (_ account: String) -> Void

    static var keychain: SecretStore {
        SecretStore(
            read: { KeychainStore.read(account: $0) },
            write: { try KeychainStore.write($0, account: $1) },
            delete: { KeychainStore.delete(account: $0) }
        )
    }
}

enum KeychainError: Error {
    case status(OSStatus)
}
