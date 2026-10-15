import AVFoundation
import XCTest
@testable import Ghostty

final class SystemSpeechRendererTests: XCTestCase {
    @MainActor
    func testRealMemoryAudioDurationAndCancellation() async throws {
        let renderer = SystemSpeechRenderer()
        let clip = try await renderer.render("你好，这是合成测试，不包含私人内容。")
        let player = try AVAudioPlayer(data: clip.data)
        XCTAssertGreaterThan(clip.frameCount, 0)
        XCTAssertGreaterThan(clip.duration, 0)
        XCTAssertEqual(player.duration, clip.duration, accuracy: 0.001)
        let canceled = Task { try await renderer.render("已取消的合成测试") }
        canceled.cancel()
        do {
            _ = try await canceled.value
            XCTFail("已取消任务不能返回可播放结果")
        } catch is CancellationError { }
    }
}
