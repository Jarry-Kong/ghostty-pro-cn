import Foundation

@main
struct LocalSessionCheck {
    @MainActor
    static func main() throws {
        let sample = ClaudeSessionRecord(id: "a'$(echo unexpected)", file: URL(fileURLWithPath: "/tmp/sample"),
                                         workingDirectory: "/tmp", lastActivity: Date(), lastPrompt: "")
        precondition(!sample.isValidResumeID)
        precondition(sample.resumeCommand == "claude --resume 'a'\"'\"'$(echo unexpected)'")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.jsonl")
        let bytes = Data("""
        {"type":"user","sessionId":"sample-1","cwd":"/tmp","timestamp":"2026-10-05T01:00:00Z","message":{"content":[{"type":"text","text":"中文样例"}]}}
        损坏行
        {"type":"user","sessionId":"ignored","cwd":"/wrong","isSidechain":true}
        """.utf8)
        try bytes.write(to: file)
        let parsed = try ClaudeSessionScanner.read(file: file)
        precondition(parsed?.id == "sample-1")
        precondition(parsed?.lastPrompt == "中文样例")
        precondition(parsed?.workingDirectory == "/tmp")
        precondition(parsed?.isValidResumeID == true)
        let after = try Data(contentsOf: file)
        precondition(after == bytes)
        precondition(parsed?.displayName == "（这个会话没起过名字）")
        let namedBytes = bytes + Data("\n{\"customTitle\":\"测试名称\"}\n{\"aiTitle\":\"模型名称\"}".utf8)
        try namedBytes.write(to: file)
        let named = try ClaudeSessionScanner.read(file: file)
        precondition(named?.name == "测试名称" && named?.nameSource == .custom)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let model = SessionLibraryModel()
        var boundary = ClaudeSessionRecord(id: "boundary", file: file, workingDirectory: "/tmp",
                                          lastActivity: now.addingTimeInterval(-604800), lastPrompt: "问题")
        boundary.name = "测试名称"
        var running = ClaudeSessionRecord(id: "running", file: file, workingDirectory: "/tmp",
                                         lastActivity: now, lastPrompt: "运行中")
        running.runningPID = 123
        var unknown = ClaudeSessionRecord(id: "unknown", file: file, workingDirectory: "/tmp",
                                         lastActivity: now, lastPrompt: "待确认")
        unknown.runningStateUnknown = true
        model.records = [boundary, running, unknown]
        model.filter = .recent
        precondition(model.visibleRecords(at: now).count == 3)
        model.filter = .idle
        precondition(model.visibleRecords(at: now).map(\.id) == ["boundary"])
        model.keyword = "测试名称"
        precondition(model.visibleRecords(at: now).count == 1)
        model.keyword = ""
        model.filter = .all
        model.selectAllVisible()
        precondition(model.selection == ["boundary"])
        let id = "12345678-1234-1234-1234-123456789abc"
        precondition(ClaudeSessionProcesses.sessionID(arguments: ["claude", "--resume", id]) == id)
        precondition(ClaudeSessionProcesses.sessionID(arguments: ["claude", "prompt mentions " + id]) == nil)
        print("独立检查通过：扫描、原字节不变、名称／预览分离、筛选边界、全选和进程参数")
        if CommandLine.arguments.count > 1 {
            let fixture = Process()
            fixture.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
            fixture.arguments = ["--resume", id]
            try fixture.run()
            defer { if fixture.isRunning { fixture.terminate() }; fixture.waitUntilExit() }
            var found = false
            for _ in 0..<20 {
                let snapshot = ClaudeSessionProcesses.snapshot()
                if snapshot.sessions[id] == fixture.processIdentifier && snapshot.ownedSessions.contains(id) { found = true; break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            precondition(found, "没有识别受控测试 Claude 进程")
            print("真实进程探测通过：仅启动模拟进程，未调用 Claude 服务或读取会话内容")
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        let records = try ClaudeSessionScanner.scan(root: root)
        // 不输出对话内容、会话编号或目录，避免诊断日志泄露隐私。
        print("只读扫描成功：\(records.count) 个会话")
        print("具有活动时间：\(records.filter { $0.lastActivity != .distantPast }.count) 个")
        let snapshot = ClaudeSessionProcesses.snapshot()
        print("运行探测摘要：编号 \(snapshot.sessions.count) 个，未定位目录 \(snapshot.unidentifiedDirectories.count) 个，检查失败 \(snapshot.inspectionFailed)")
    }
}
