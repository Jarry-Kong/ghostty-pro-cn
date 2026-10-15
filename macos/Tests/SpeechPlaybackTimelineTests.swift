import XCTest
@testable import Ghostty

final class SpeechPlaybackTimelineTests: XCTestCase {
    func testCumulativeDurationAndBoundaryLocations() throws {
        let timeline = try SpeechPlaybackTimeline(durations: [2, 3])
        XCTAssertEqual(timeline.starts, [0, 2])
        XCTAssertEqual(timeline.total, 5)
        XCTAssertEqual(timeline.location(at: 2)?.index, 1)
        XCTAssertEqual(timeline.location(at: 5)?.offset, 3)
        XCTAssertEqual(timeline.location(at: -1)?.offset, 0)
        XCTAssertNil(timeline.location(at: .nan))
        XCTAssertThrowsError(try SpeechPlaybackTimeline(durations: []))
        XCTAssertThrowsError(try SpeechPlaybackTimeline(durations: [0]))
        XCTAssertThrowsError(try SpeechPlaybackTimeline(durations: [.infinity]))
    }

    func testTranscriptTimelineUsesPlayedClipOrderAndDurations() throws {
        let clips = [
            SpeechAudioSegment(text: "第一段", audio: RenderedSpeechClip(data: Data(), duration: 1.25, frameCount: 0)),
            SpeechAudioSegment(text: "第二段", audio: RenderedSpeechClip(data: Data(), duration: 2.5, frameCount: 0)),
        ]

        let segments = try SpeechSegment.timed(clips)

        XCTAssertEqual(segments.map(\.text), ["第一段", "第二段"])
        XCTAssertEqual(segments.map(\.startTime), [0, 1.25])
        XCTAssertEqual(segments.compactMap(\.endTime), [1.25, 3.75])
    }
}
