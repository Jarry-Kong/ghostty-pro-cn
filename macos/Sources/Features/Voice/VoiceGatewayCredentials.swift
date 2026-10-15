import Foundation
import Security
import LocalAuthentication

/// 只访问恢复版自己的命名空间，不探测原版或其他应用的凭据。
enum VoiceGatewayCredentials {
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "钥匙串操作失败（\(status)），内存令牌和其他凭据未被删除。" }
    }

    static func query(endpoint: URL, service: String = "com.mitchellh.ghostty.recovered.voice.gateway") throws -> [String: Any] {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host?.isEmpty == false,
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil else {
            throw URLError(.badURL)
        }
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: endpoint.absoluteString,
                kSecUseAuthenticationContext as String: context]
    }

    static func save(_ token: String, endpoint: URL, service: String = "com.mitchellh.ghostty.recovered.voice.gateway") throws {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              token.rangeOfCharacter(from: .controlCharacters) == nil, token.utf8.count <= 16 * 1024 else {
            throw URLError(.userAuthenticationRequired)
        }
        let query = try query(endpoint: endpoint, service: service)
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func read(endpoint: URL, service: String = "com.mitchellh.ghostty.recovered.voice.gateway") throws -> String? {
        var query = try query(endpoint: endpoint, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return token
    }
}
