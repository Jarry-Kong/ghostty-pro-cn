import XCTest
@testable import Ghostty

final class ClaudeReplyReaderTests: XCTestCase {
    func testDirectoryAndNormalizedTitleMatching() {
        func record(_ name: String, cwd: String = "/tmp") -> ClaudeSessionRecord {
            ClaudeSessionRecord(id: UUID().uuidString, file: URL(fileURLWithPath: "/tmp/test"),
                                workingDirectory: cwd, lastActivity: Date(), lastPrompt: "", name: name)
        }
        let recent = record("最近的其他对话")
        let exact = record("恢复功能测试")
        let foreign = record("恢复功能测试", cwd: "/different")
        XCTAssertEqual(ClaudeReplyLocator.normalizedTitle(" ✱🧪 恢复功能测试 "), "恢复功能测试")
        XCTAssertEqual(ClaudeReplyLocator.select(records: [foreign, recent, exact], cwd: "/tmp",
                                                terminalTitle: "✱ 恢复功能测试")?.id, exact.id)
        XCTAssertEqual(ClaudeReplyLocator.select(records: [recent, exact], cwd: "/tmp",
                                                terminalTitle: "恢复功能测试 - Claude")?.id, exact.id)
        XCTAssertEqual(ClaudeReplyLocator.select(records: [recent, exact], cwd: "/tmp", terminalTitle: nil)?.id, recent.id)
        XCTAssertNil(ClaudeReplyLocator.select(records: [foreign], cwd: "/tmp", terminalTitle: nil))
    }
    func testOnlyTargetAssistantTextIsRead() throws {
        let id = UUID().uuidString
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(id + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let lines: [[String: Any]] = [
            ["type": "user", "sessionId": id, "message": ["content": "不朗读用户提问"]],
            ["type": "assistant", "sessionId": id, "timestamp": "2026-10-06T00:00:00Z",
             "message": ["content": [["type": "text", "text": "第一段"], ["type": "tool_use", "name": "隐藏工具"],
                                      ["type": "thinking", "thinking": "隐藏思考"], ["type": "text", "text": "第二段"]]]],
            ["type": "assistant", "sessionId": UUID().uuidString, "message": ["content": "其他会话"]],
            ["type": "assistant", "sessionId": id, "isSidechain": true, "message": ["content": "子代理"]],
            ["type": "assistant", "sessionId": id, "isApiErrorMessage": true, "message": ["content": "错误回复"]],
            ["type": "assistant", "sessionId": id, "message": ["content": [["type": "tool_use", "name": "工具"]]]]
        ]
        var data = Data("损坏行\n".utf8)
        for line in lines { data.append(try JSONSerialization.data(withJSONObject: line)); data.append(10) }
        try data.write(to: file)
        let reply = try XCTUnwrap(ClaudeReplyReader.latestReply(in: file, sessionID: id))
        XCTAssertEqual(reply.text, "第一段\n第二段")
        XCTAssertNotNil(reply.timestamp)
        XCTAssertThrowsError(try ClaudeReplyReader.latestReply(in: file, sessionID: UUID().uuidString))
    }
}
