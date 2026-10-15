import Foundation

@main
enum SegmentedPlaybackCheck {
    @MainActor static func main() async throws {
        let timeline = try SpeechPlaybackTimeline(durations: [2, 3])
        precondition(timeline.total == 5 && timeline.location(at: 2)?.index == 1)
        precondition(timeline.location(at: -1)?.offset == 0)
        precondition(timeline.location(at: .nan) == nil)
        do { _ = try SpeechPlaybackTimeline(durations: [0]); preconditionFailure("零时长未拒绝") } catch { }
        let renderer = SystemSpeechRenderer()
        let job = Task { try await renderer.render("这是分段播放检查，不包含私人内容。") }
        let timeout = Task { try await Task.sleep(nanoseconds: 30_000_000_000); job.cancel() }
        defer { timeout.cancel() }
        let audio = try await job.value
        precondition(audio.fileExtension == "wav")
        precondition(RenderedSpeechClip(data: Data("ID3test".utf8), duration: 1, frameCount: 0).fileExtension == "mp3")
        precondition(RenderedSpeechClip(data: Data([0xff, 0xfb]), duration: 1, frameCount: 0).fileExtension == "mp3")
        precondition(RenderedSpeechClip(data: Data([0, 0, 0, 24]) + Data("ftypM4A ".utf8), duration: 1, frameCount: 0).fileExtension == "m4a")
        precondition(RenderedSpeechClip(data: Data(), duration: 1, frameCount: 0).fileExtension == "audio")
        let verifiedDuration = try SpeechPlayer.validatedDuration(of: audio.data)
        precondition(abs(verifiedDuration - audio.duration) < 0.001)
        let encoded = try JSONSerialization.data(withJSONObject: ["audio_data": audio.data.base64EncodedString()])
        switch try QwenTTSResponse.decode(encoded, statusCode: 200) {
        case let .bytes(_, data):
            let duration = try SpeechPlayer.validatedDuration(of: data)
            precondition(data == audio.data && abs(duration - audio.duration) < 0.001)
        case .url: preconditionFailure("合成 Base64 不应识别为地址")
        }
        for data in [Data(), Data("不是音频".utf8)] {
            do { _ = try SpeechPlayer.validatedDuration(of: data); preconditionFailure("非法音频必须拒绝") }
            catch { }
        }
        let player = SegmentedSpeechPlayer()
        let clips = [SpeechAudioSegment(text: "第一段", audio: audio), SpeechAudioSegment(text: "第二段", audio: audio)]
        try player.play(clips, startPaused: true)
        precondition(player.isActive && player.isPaused && player.currentIndex == 0)
        player.rate = 1.5
        try player.seek(to: audio.duration + 0.1)
        precondition(player.currentIndex == 1 && player.isPaused)
        precondition(abs(player.position - audio.duration - 0.1) < 0.001)
        try player.seek(to: player.duration)
        precondition(!player.isActive && player.position == player.duration)
        try player.play(clips, startPaused: true)
        try player.jump(to: 0)
        player.stop()
        await Task.yield()
        precondition(!player.isActive && !player.isPaused && player.position == 0)
        print("分段检查通过：真实音频、累计时长、暂停跨段定位、结束边界、停止后排队回调隔离")
    }
}
