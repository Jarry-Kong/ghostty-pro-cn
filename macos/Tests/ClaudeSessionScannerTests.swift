import XCTest
@testable import Ghostty

final class ClaudeSessionScannerTests: XCTestCase {
    func testOriginalSidecarTitleFallbackAndReadOnlyBehavior() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: project) }
        let id = UUID().uuidString
        let directory = project.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = project.appendingPathComponent(id + ".jsonl")
        let input = Data("""
        {"type":"user","sessionId":"\(id)","cwd":"/tmp","message":{"content":"问题"}}
        {"type":"ai-title","aiTitle":"模型名称"}
        """.utf8)
        try input.write(to: file)
        let sidecar = directory.appendingPathComponent("custom-title.json")
        let titleData = Data("{\"customTitle\":\"外置中文名称\"}".utf8)
        try titleData.write(to: sidecar)
        let record = try XCTUnwrap(ClaudeSessionScanner.read(file: file))
        XCTAssertEqual(record.name, "外置中文名称")
        XCTAssertEqual(record.nameSource, .custom)
        XCTAssertEqual(try Data(contentsOf: file), input)
        XCTAssertEqual(try Data(contentsOf: sidecar), titleData)
        try Data("损坏文件".utf8).write(to: sidecar)
        XCTAssertEqual(try ClaudeSessionScanner.read(file: file)?.name, "模型名称")
    }
    func testForeignSessionLineCannotChangeResumeTarget() throws {
        let id = UUID().uuidString
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(id + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let input = """
        {"type":"user","sessionId":"\(id)","cwd":"/tmp","message":{"content":"正确问题"}}
        {"type":"user","sessionId":"\(UUID().uuidString)","cwd":"/wrong","message":{"content":"别的会话"}}
        """
        try Data(input.utf8).write(to: file)
        let record = try XCTUnwrap(ClaudeSessionScanner.read(file: file))
        XCTAssertEqual(record.id, id.lowercased())
        XCTAssertEqual(record.workingDirectory, "/tmp")
        XCTAssertEqual(record.lastPrompt, "正确问题")
    }
    @MainActor
    func testOriginalDateGroupLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!
        for (days, label) in [(0, "今天"), (1, "昨天"), (6, "最近 7 天"), (7, "本月更早"), (29, "本月更早"), (30, "更早")] {
            let date = calendar.date(byAdding: .day, value: -days, to: now)!
            XCTAssertEqual(SessionLibraryModel.groupTitle(for: date, now: now, calendar: calendar), label)
        }
    }
    func testResumeCommandQuotesShellMetacharacters() {
        let record = ClaudeSessionRecord(id: "a'$(touch /tmp/not-executed)", file: URL(fileURLWithPath: "/tmp/a"),
                                        workingDirectory: "/tmp", lastActivity: Date(), lastPrompt: "")
        XCTAssertEqual(record.resumeCommand, "claude --resume 'a'\"'\"'$(touch /tmp/not-executed)'")
        XCTAssertEqual(record.displayName, "（这个会话没起过名字）")
        XCTAssertFalse(record.isValidResumeID)
        let option = ClaudeSessionRecord(id: "--dangerously-skip-permissions", file: record.file,
                                        workingDirectory: "/tmp", lastActivity: Date(), lastPrompt: "")
        XCTAssertFalse(option.isValidResumeID)
    }

    func testOriginalTitleKeysAndPreviewSeparation() throws {
        let id = UUID().uuidString
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(id + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let input = """
        {"type":"user","sessionId":"\(id)","cwd":"/tmp","message":{"content":"问题不是名称"}}
        {"type":"custom-title","customTitle":"自定义中文名"}
        {"type":"ai-title","aiTitle":"模型名"}
        """
        try Data(input.utf8).write(to: file)
        let record = try XCTUnwrap(ClaudeSessionScanner.read(file: file))
        XCTAssertEqual(record.displayName, "自定义中文名")
        XCTAssertEqual(record.nameSource, .custom)
        XCTAssertEqual(record.preview, "问题不是名称")
    }

    func testExplicitProcessArgumentsDoNotMatchSubstringOrEnvironment() {
        let id = "12345678-1234-1234-1234-123456789abc"
        XCTAssertEqual(ClaudeSessionProcesses.sessionID(arguments: ["claude", "--resume", id]), id)
        XCTAssertEqual(ClaudeSessionProcesses.sessionID(arguments: ["claude", "--session-id=\(id)"]), id)
        XCTAssertNil(ClaudeSessionProcesses.sessionID(arguments: ["claude", "prompt mentions \(id)"]))
        XCTAssertNil(ClaudeSessionProcesses.sessionID(arguments: ["claude", "--resume", "not-a-uuid"]))
        XCTAssertNil(ClaudeSessionProcesses.sessionID(arguments: ["claude", "--", "--resume", id]))
        XCTAssertTrue(ClaudeSessionProcesses.isNativeClaude("/usr/local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"))
        XCTAssertFalse(ClaudeSessionProcesses.isNativeClaude("/tmp/unrelated/claude.exe"))
        var snapshot = ClaudeSessionProcesses.Snapshot()
        snapshot.unidentifiedDirectories.insert(URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path)
        XCTAssertTrue(snapshot.isUncertain(directory: "/tmp"))
        snapshot.activeDirectories.insert(URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path)
        XCTAssertTrue(snapshot.isActive(directory: "/tmp/../tmp"))
        XCTAssertFalse(snapshot.isActive(directory: "/var"))
    }

    func testSessionUUIDIsNormalizedForProcessAndWindowIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let uppercase = "89F74A8B-5999-48F2-84D2-C7859C0A8D40"
        let file = directory.appendingPathComponent(uppercase + ".jsonl")
        try Data("""
        {"sessionId":"\(uppercase)","cwd":"/tmp","timestamp":"2026-10-13T00:00:00Z"}
        """.utf8).write(to: file)

        let record = try XCTUnwrap(ClaudeSessionScanner.read(file: file))

        XCTAssertEqual(record.id, uppercase.lowercased())
        XCTAssertEqual(ClaudeSessionProcesses.sessionID(arguments: ["claude", "--resume", uppercase]), uppercase.lowercased())
    }

    @MainActor
    func testFilterBoundaryNameSearchAndSelection() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let model = SessionLibraryModel()
        var boundary = ClaudeSessionRecord(id: "a", file: URL(fileURLWithPath: "/tmp/a"),
                                          workingDirectory: "/tmp", lastActivity: now.addingTimeInterval(-604800), lastPrompt: "问题")
        boundary.name = "自定义名"
        var running = boundary
        running = ClaudeSessionRecord(id: "b", file: URL(fileURLWithPath: "/tmp/b"), workingDirectory: "/tmp",
                                      lastActivity: now, lastPrompt: "另一个问题")
        running.runningPID = 123
        var unknown = running
        unknown = ClaudeSessionRecord(id: "c", file: URL(fileURLWithPath: "/tmp/c"), workingDirectory: "/tmp",
                                      lastActivity: now, lastPrompt: "待确认")
        unknown.runningStateUnknown = true
        model.records = [boundary, running, unknown]
        model.filter = .recent
        XCTAssertEqual(model.visibleRecords(at: now).count, 3)
        model.filter = .idle
        XCTAssertEqual(model.visibleRecords(at: now).map(\.id), ["a"])
        model.keyword = "自定义名"
        XCTAssertEqual(model.visibleRecords(at: now).map(\.id), ["a"])
        model.filter = .all
        model.keyword = ""
        model.selectAllVisible()
        XCTAssertEqual(model.selection, ["a"])
    }
    func testReadOnlyScanHandlesMalformedLineAndSidechain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("session.jsonl")
        let input = """
        {"type":"user","sessionId":"session-1","cwd":"/tmp","timestamp":"2026-10-04T01:00:00.000Z","message":{"content":"中文请求"}}
        损坏的一行
        {"type":"user","sessionId":"sidechain","cwd":"/wrong","isSidechain":true,"message":{"content":"忽略"}}
        {"type":"last-prompt","sessionId":"session-1","lastPrompt":"最新问题"}
        """
        let bytes = Data(input.utf8)
        try bytes.write(to: file)
        let records = try ClaudeSessionScanner.scan(root: root)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, "session-1")
        XCTAssertEqual(records.first?.workingDirectory, "/tmp")
        XCTAssertEqual(records.first?.lastPrompt, "最新问题")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testMissingRootAndUnusableRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(try ClaudeSessionScanner.scan(root: root).isEmpty)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{\"type\":\"user\"}".utf8).write(to: file)
        XCTAssertNil(try ClaudeSessionScanner.read(file: file))
    }

    func testLargeRecordCrossesReadChunksWithoutChangingSource() throws {
        let id = UUID().uuidString.lowercased()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(id + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let prompt = String(repeating: "中文内容", count: 20_000)
        let value: [String: Any] = [
            "type": "user", "sessionId": id, "cwd": "/tmp",
            "timestamp": "2026-10-13T01:02:03Z", "message": ["content": prompt],
        ]
        let bytes = try JSONSerialization.data(withJSONObject: value) + Data([10])
        try bytes.write(to: file)

        let record = try XCTUnwrap(ClaudeSessionScanner.read(file: file))
        XCTAssertEqual(record.lastPrompt, prompt)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testDuplicateSessionKeepsNewestActivity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID().uuidString.lowercased()
        for (projectName, timestamp, prompt) in [
            ("old", "2026-10-12T01:00:00Z", "旧问题"),
            ("new", "2026-10-13T01:00:00Z", "新问题"),
        ] {
            let project = root.appendingPathComponent(projectName)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let line = """
            {"type":"user","sessionId":"\(id)","cwd":"/tmp","timestamp":"\(timestamp)","message":{"content":"\(prompt)"}}
            """
            try Data(line.utf8).write(to: project.appendingPathComponent(id + ".jsonl"))
        }

        let records = try ClaudeSessionScanner.scan(root: root)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.lastPrompt, "新问题")
    }

    func testScanDoesNotFollowDirectoryOrRecordSymlinks() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? manager.removeItem(at: root)
            try? manager.removeItem(at: outside)
        }
        let project = root.appendingPathComponent("project")
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let outsideFile = outside.appendingPathComponent(id + ".jsonl")
        let line = "{\"type\":\"user\",\"sessionId\":\"\(id)\",\"cwd\":\"/tmp\",\"message\":{\"content\":\"不应读取\"}}"
        try Data(line.utf8).write(to: outsideFile)
        try manager.createSymbolicLink(at: root.appendingPathComponent("linked-project"), withDestinationURL: outside)
        try manager.createSymbolicLink(at: project.appendingPathComponent(id + ".jsonl"), withDestinationURL: outsideFile)

        XCTAssertTrue(try ClaudeSessionScanner.scan(root: root).isEmpty)
    }
}
