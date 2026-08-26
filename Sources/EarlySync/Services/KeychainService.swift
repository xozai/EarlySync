import Foundation
import Security

// MARK: - Keychain Keys

private enum KeychainKey {
    static let earlyAPIKey = "com.earlysync.early.apiKey"
    static let earlyAPISecret = "com.earlysync.early.apiSecret"
    static let earlyToken = "com.earlysync.early.token"
    static let luxaforUserId = "com.earlysync.luxafor.userId"
}

// MARK: - KeychainService

/// Wraps macOS Keychain for secure credential storage.
/// All credentials (Early API key/secret, token, Luxafor userId) live here —
/// never in UserDefaults or on disk.
public final class KeychainService {

    public static let shared = KeychainService()
    private init() {}

    // MARK: - Early API Credentials

    public var earlyAPIKey: String? {
        get { load(key: KeychainKey.earlyAPIKey) }
        set { save(key: KeychainKey.earlyAPIKey, value: newValue) }
    }

    public var earlyAPISecret: String? {
        get { load(key: KeychainKey.earlyAPISecret) }
        set { save(key: KeychainKey.earlyAPISecret, value: newValue) }
    }

    public var earlyToken: String? {
        get { load(key: KeychainKey.earlyToken) }
        set { save(key: KeychainKey.earlyToken, value: newValue) }
    }

    public var luxaforUserId: String? {
        get { load(key: KeychainKey.luxaforUserId) }
        set { save(key: KeychainKey.luxaforUserId, value: newValue) }
    }

    // MARK: - Helpers

    public func hasEarlyCredentials() -> Bool {
        earlyAPIKey != nil && earlyAPISecret != nil
    }

    public func clearAll() {
        for key in [
            KeychainKey.earlyAPIKey,
            KeychainKey.earlyAPISecret,
            KeychainKey.earlyToken,
            KeychainKey.luxaforUserId,
        ] {
            delete(key: key)
        }
    }

    // MARK: - Private Keychain Primitives

    private func save(key: String, value: String?) {
        if let value {
            let data = Data(value.utf8)
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: key,
                kSecValueData: data,
            ]
            // Try update first, then add
            let updateFields: [CFString: Any] = [kSecValueData: data]
            let status = SecItemUpdate(query as CFDictionary, updateFields as CFDictionary)
            if status == errSecItemNotFound {
                SecItemAdd(query as CFDictionary, nil)
            }
        } else {
            delete(key: key)
        }
    }

    private func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    private func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
