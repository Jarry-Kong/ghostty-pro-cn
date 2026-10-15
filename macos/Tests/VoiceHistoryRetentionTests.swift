import XCTest
@testable import Ghostty

final class VoiceHistoryRetentionTests: XCTestCase {
    func testExactBoundaryAndOldestRemovalWithoutMutation() throws {
        let first = VoiceHistoryRetention.Item(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), bytes: 100)
        let second = VoiceHistoryRetention.Item(id: UUID(), createdAt: Date(timeIntervalSince1970: 2), bytes: 100)
        XCTAssertTrue(try VoiceHistoryRetention.removals([second, first], maxCount: 2, maxBytes: 200).isEmpty)
        XCTAssertEqual(try VoiceHistoryRetention.removals([second, first], maxCount: 1, maxBytes: 200), [first.id])
        XCTAssertEqual(try VoiceHistoryRetention.removals([second, first], maxCount: 2, maxBytes: 199), [first.id])
        XCTAssertThrowsError(try VoiceHistoryRetention.removals([first, first]))
        let sameSecond = VoiceHistoryRetention.Item(id: UUID(), createdAt: first.createdAt, bytes: 100)
        XCTAssertEqual(try VoiceHistoryRetention.removals([sameSecond, first], maxCount: 1, maxBytes: 200), [first.id])
    }
}
