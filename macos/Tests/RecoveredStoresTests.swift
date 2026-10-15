import XCTest
@testable import Ghostty

final class RecoveredStoresTests: XCTestCase {
    func testSessionRoundTripAndMissingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionLibraryStore(fileURL: directory.appendingPathComponent("sessions.json"))
        XCTAssertTrue(try store.load().isEmpty)
        let record = SessionRecord(title: "中文会话", directory: "/tmp", isPinned: true)
        try store.save([record])
        let restored = try XCTUnwrap(store.load().first)
        XCTAssertEqual(restored.id, record.id)
        XCTAssertEqual(restored.title, record.title)
        XCTAssertEqual(restored.directory, "/tmp")
        XCTAssertTrue(restored.isPinned)
    }

    func testVoiceHistoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VoiceHistoryStore(fileURL: directory.appendingPathComponent("voice.json"))
        let entry = VoiceHistoryEntry(text: "你好，世界", summary: "选中内容", projectName: "ghostty", terminalTitle: "开发")
        try store.save([entry])
        let restored = try XCTUnwrap(store.load().first)
        XCTAssertEqual(restored.text, entry.text)
        XCTAssertEqual(restored.summary, "选中内容")
        XCTAssertEqual(restored.displaySummary, "选中内容")
        XCTAssertEqual(restored.projectName, "ghostty")
        XCTAssertEqual(restored.terminalTitle, "开发")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(entry)) as? [String: Any])
        legacy.removeValue(forKey: "projectName")
        legacy.removeValue(forKey: "terminalTitle")
        legacy.removeValue(forKey: "summary")
        try JSONSerialization.data(withJSONObject: [legacy]).write(to: directory.appendingPathComponent("voice.json"))
        let old = try XCTUnwrap(store.load().first)
        XCTAssertNil(old.projectName)
        XCTAssertNil(old.terminalTitle)
        XCTAssertNil(old.summary)
        XCTAssertEqual(old.displaySummary, "你好，世界")
    }
}
