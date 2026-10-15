import Foundation
import Security
import LocalAuthentication

@main
enum CheckCredentialQuery {
    static func main() throws {
        let first = try VoiceGatewayCredentials.query(endpoint: URL(string: "https://example.invalid/bailian/audio/tts")!)
        let other = try VoiceGatewayCredentials.query(endpoint: URL(string: "https://other.invalid/bailian/audio/tts")!)
        let prefix = try VoiceGatewayCredentials.query(endpoint: URL(string: "https://example.invalid/team/bailian/audio/tts")!)
        precondition(first[kSecAttrService as String] as? String == "com.mitchellh.ghostty.recovered.voice.gateway")
        precondition(first[kSecAttrAccount as String] as? String != other[kSecAttrAccount as String] as? String)
        precondition(first[kSecAttrAccount as String] as? String != prefix[kSecAttrAccount as String] as? String)
        precondition(first[kSecValueData as String] == nil)
        precondition((first[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
        for address in ["http://example.invalid/tts", "https://user:secret@example.invalid/tts", "https://example.invalid/tts?token=secret"] {
            do { _ = try VoiceGatewayCredentials.query(endpoint: URL(string: address)!); preconditionFailure("非法凭据作用域必须拒绝") }
            catch is URLError { }
        }
        print("凭据查询检查通过：独立命名空间、地址隔离、无令牌、拒绝不安全地址；未调用 SecItem 或访问真实钥匙串")
    }
}
