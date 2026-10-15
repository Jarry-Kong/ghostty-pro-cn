import Foundation

@main
enum LatestReplyCheck {
    static func main() async throws {
        let id = UUID().uuidString
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(id + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let rows: [[String: Any]] = [
            ["type": "assistant", "sessionId": id, "message": ["content": [["type": "text", "text": "合成测试回复"],
                ["type": "tool_use", "name": "不得朗读工具"]]]],
            ["type": "user", "sessionId": id, "message": ["content": "不得朗读提问"]],
            ["type": "assistant", "sessionId": UUID().uuidString, "message": ["content": "不得读其他会话"]],
            ["type": "assistant", "sessionId": id, "isApiErrorMessage": true, "message": ["content": "不得读错误"]]
        ]
        var input = Data("损坏行\n".utf8)
        for row in rows { input.append(try JSONSerialization.data(withJSONObject: row)); input.append(10) }
        try input.write(to: file)
        let reply = try ClaudeReplyReader.latestReply(in: file, sessionID: id)
        precondition(reply?.text == "合成测试回复")
        let unchanged = try Data(contentsOf: file)
        precondition(unchanged == input)
        let cancelledRead = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try ClaudeReplyReader.latestReply(in: file, sessionID: id)
        }
        cancelledRead.cancel()
        do {
            _ = try await cancelledRead.value
            preconditionFailure("取消后不得继续返回回复")
        } catch is CancellationError { }
        let afterCancellation = try Data(contentsOf: file)
        precondition(afterCancellation == input)
        let cancelledScan = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try ClaudeReplyLocator.find(root: file.deletingLastPathComponent(), cwd: "/tmp", terminalTitle: nil)
        }
        cancelledScan.cancel()
        do {
            _ = try await cancelledScan.value
            preconditionFailure("取消后不得继续定位会话")
        } catch is CancellationError { }
        let recent = ClaudeSessionRecord(id: UUID().uuidString, file: file, workingDirectory: "/tmp",
                                        lastActivity: Date(), lastPrompt: "", name: "另一条对话")
        let target = ClaudeSessionRecord(id: id, file: file, workingDirectory: "/tmp",
                                        lastActivity: Date(), lastPrompt: "", name: "功能恢复测试")
        precondition(ClaudeReplyLocator.normalizedTitle("🧪 ✱ 功能恢复测试 ✴") == "功能恢复测试")
        precondition(ClaudeReplyLocator.select(records: [recent, target], cwd: "/tmp",
                                               terminalTitle: "✱ 功能恢复测试")?.id == id)
        precondition(ClaudeReplyLocator.select(records: [recent, target], cwd: "/tmp",
                                               terminalTitle: "功能恢复测试 - Claude")?.id == id)
        precondition(ClaudeReplyLocator.select(records: [recent, target], cwd: "/elsewhere", terminalTitle: nil) == nil)
        precondition(ClaudeReplyLocator.select(records: [recent, target], cwd: "/tmp", terminalTitle: nil)?.id == recent.id)
        print("最新回复检查通过：目标文字及排除边界、文件不变、标题规范化、精确／包含匹配、目录隔离及原版最近回退")
    }
}
