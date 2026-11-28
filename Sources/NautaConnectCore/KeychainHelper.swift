import Foundation
import Security

public struct KeychainSaveError: LocalizedError, Equatable {
    public let status: OSStatus

    public init(status: OSStatus) { self.status = status }

    public var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? L10n.t(.keychainFailure)
    }
}

/// Minimal generic-password Keychain wrapper. The Nauta password never
/// touches UserDefaults or disk in plain text.
public enum KeychainHelper {
    private static let service = "com.nautaconnect.macos"

    @discardableResult
    public static func savePassword(_ password: String, account: String) -> Bool {
        savePasswordStatus(password, account: account) == errSecSuccess
    }

    public static func savePasswordStatus(_ password: String, account: String) -> OSStatus {
        savePasswordStatus(password, account: account,
                           update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
                           add: { SecItemAdd($0 as CFDictionary, nil) })
    }

    static func savePasswordStatus(_ password: String, account: String,
                                   update: ([String: Any], [String: Any]) -> OSStatus,
                                   add: ([String: Any]) -> OSStatus) -> OSStatus {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8)]
        let updateStatus = update(query, attributes)
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        var newItem = query
        newItem[kSecValueData as String] = attributes[kSecValueData as String]
        let addStatus = add(newItem)
        // Another writer may have inserted the item after our update.
        if addStatus == errSecDuplicateItem { return update(query, attributes) }
        return addStatus
    }

    public static func loadPassword(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    public static func deletePassword(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
