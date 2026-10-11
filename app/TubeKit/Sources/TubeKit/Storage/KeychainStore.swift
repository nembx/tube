import Foundation
import Security

/// 极简 Keychain 封装：按 service + account 存取一段 `Data`。
///
/// 只用来放 Bangumi 的 OAuth token（含 refresh_token）—— 这类凭证比收藏状态敏感，
/// 不该躺在 UserDefaults 里。`kSecAttrAccessibleAfterFirstUnlock` 保证锁屏后台也能刷新。
public enum KeychainStore {
    public enum Error: Swift.Error, Sendable {
        case status(OSStatus)
    }

    private static let service = "com.nembx.tube.bangumi"

    /// 写入（覆盖已有）。空 data 视为删除。
    public static func set(_ data: Data, account: String) throws {
        guard !data.isEmpty else {
            try remove(account: account)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw Error.status(updateStatus)
        }
        var insert = query
        insert.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Error.status(addStatus)
        }
    }

    public static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    public static func remove(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.status(status)
        }
    }
}
