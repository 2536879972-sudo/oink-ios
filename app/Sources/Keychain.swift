import Foundation
import Security

/// 自签 App 常常拿不到 keychain-access-groups entitlement，
/// 写入会返回 errSecMissingEntitlement。所以做 Keychain + UserDefaults 双写，
/// Keychain 不可用时自动降级，保证自签环境一定能存住。
enum SecureStore {

    private static let service = "com.operator.oink.chat"

    static func set(_ value: String, key: String) {
        Keychain.save(value, service: service, account: key)
        // 回读确认，失败则落 UserDefaults
        if Keychain.load(service: service, account: key) == nil {
            UserDefaults.standard.set(value, forKey: "secure." + key)
        } else {
            UserDefaults.standard.removeObject(forKey: "secure." + key)
        }
    }

    static func get(key: String) -> String? {
        if let v = Keychain.load(service: service, account: key) {
            return v
        }
        return UserDefaults.standard.string(forKey: "secure." + key)
    }

    static func remove(key: String) {
        Keychain.delete(service: service, account: key)
        UserDefaults.standard.removeObject(forKey: "secure." + key)
    }
}

enum Keychain {

    static func save(_ value: String, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
