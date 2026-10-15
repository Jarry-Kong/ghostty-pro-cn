import Foundation
import Security

@main
enum CheckGatewayKeychain {
    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--read-test" {
            let service = CommandLine.arguments[2]
            precondition(service.hasPrefix("Ghostty-Recovery-Test-") && UUID(uuidString: String(service.dropFirst("Ghostty-Recovery-Test-".count))) != nil)
            let value = try VoiceGatewayCredentials.read(endpoint: URL(string: "https://example.invalid/bailian/audio/tts")!, service: service)
            precondition(value == "synthetic-first")
            return
        }
        let service = "Ghostty-Recovery-Test-" + UUID().uuidString
        let endpoint = URL(string: "https://example.invalid/bailian/audio/tts")!
        let other = URL(string: "https://other.invalid/bailian/audio/tts")!
        let query = try VoiceGatewayCredentials.query(endpoint: endpoint, service: service)
        defer {
            let status = SecItemDelete(query as CFDictionary)
            precondition(status == errSecSuccess || status == errSecItemNotFound, "测试条目清理失败")
        }
        let missing = try VoiceGatewayCredentials.read(endpoint: endpoint, service: service)
        precondition(missing == nil)
        try VoiceGatewayCredentials.save("synthetic-first", endpoint: endpoint, service: service)
        let first = try VoiceGatewayCredentials.read(endpoint: endpoint, service: service)
        precondition(first == "synthetic-first")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--read-test", service]
        try child.run()
        let timeout = DispatchWorkItem { if child.isRunning { child.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        child.waitUntilExit()
        timeout.cancel()
        precondition(child.terminationReason == .exit && child.terminationStatus == 0)
        let isolated = try VoiceGatewayCredentials.read(endpoint: other, service: service)
        precondition(isolated == nil)
        try VoiceGatewayCredentials.save("synthetic-updated", endpoint: endpoint, service: service)
        let updated = try VoiceGatewayCredentials.read(endpoint: endpoint, service: service)
        precondition(updated == "synthetic-updated")
        do { try VoiceGatewayCredentials.save("\n", endpoint: endpoint, service: service); preconditionFailure("非法令牌必须拒绝") }
        catch is URLError { }
        let unchanged = try VoiceGatewayCredentials.read(endpoint: endpoint, service: service)
        precondition(unchanged == "synthetic-updated")
        let status = SecItemDelete(query as CFDictionary)
        precondition(status == errSecSuccess)
        let removed = try VoiceGatewayCredentials.read(endpoint: endpoint, service: service)
        precondition(removed == nil)
        print("随机服务钥匙串测试通过：保存、跨进程读取、更新、地址隔离、非法值保护；测试条目已删除，无真实凭据访问")
    }
}
