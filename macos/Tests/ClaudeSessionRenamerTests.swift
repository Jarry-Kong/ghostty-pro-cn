import XCTest
@testable import Ghostty

final class ClaudeSessionRenamerTests: XCTestCase {
    func testTitleBoundaryUsesCharacters() throws {
        XCTAssertEqual(try ClaudeSessionScanner.validatedTitle(" \n中文\t"), "中文")
        XCTAssertThrowsError(try ClaudeSessionScanner.validatedTitle(" \n"))
        XCTAssertNoThrow(try ClaudeSessionScanner.validatedTitle(String(repeating: "👨‍👩‍👧‍👦", count: 120)))
        XCTAssertThrowsError(try ClaudeSessionScanner.validatedTitle(String(repeating: "字", count: 121)))
    }

    func testSidecarRenamePreservesConversationAndBackup() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let project = root.appendingPathComponent("project")
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let id = UUID().uuidString
        let file = project.appendingPathComponent(id + ".jsonl")
        let original = Data("{\"sessionId\":\"\(id)\",\"cwd\":\"/tmp\",\"aiTitle\":\"旧名称\"}\n".utf8)
        try original.write(to: file)
        let record = try XCTUnwrap(ClaudeSessionScanner.read(file: file))
        let renamed = try ClaudeSessionRenamer.rename(record, to: "新名称", root: root)
        XCTAssertEqual(renamed.name, "新名称")
        _ = try ClaudeSessionRenamer.rename(renamed, to: "第二名称", root: root)
        XCTAssertEqual(try Data(contentsOf: file), original)
        let entries = try manager.contentsOfDirectory(atPath: project.appendingPathComponent(id).path)
        XCTAssertEqual(entries.filter { $0.hasPrefix(".custom-title.backup-") }.count, 1)
        XCTAssertThrowsError(try ClaudeSessionRenamer.rename(record, to: "过期名称", root: root))
        XCTAssertThrowsError(try ClaudeSessionRenamer.rename(renamed, to: "错误根目录", root: project))
    }
}
