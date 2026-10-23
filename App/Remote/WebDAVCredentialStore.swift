// WebDAVCredentialStore.swift — WebDAV 账号持久化（密码进钥匙串）
//
// 服务器地址与用户名放 UserDefaults（非敏感），密码放 Keychain。
// 明文写 UserDefaults 是很多国内 App 的老毛病，这里不跟着犯。
import Foundation
import Security

enum WebDAVCredentialStore {
    private static let service = "com.miniretro.remote.webdav"
    private static let serverKey = "remote.webdav.server"
    private static let userKey = "remote.webdav.username"

    static var server: String {
        get { UserDefaults.standard.string(forKey: serverKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: serverKey) }
    }

    static var username: String {
        get { UserDefaults.standard.string(forKey: userKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: userKey) }
    }

    static func password(for server: String) -> String {
        guard !server.isEmpty else { return "" }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func setPassword(_ password: String, for server: String) {
        guard !server.isEmpty else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server,
        ]
        if password.isEmpty {
            SecItemDelete(base as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
