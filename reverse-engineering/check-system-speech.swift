import AVFoundation
import Foundation

@main
enum SystemSpeechCheck {
    @MainActor static func main() async throws {
        let renderer = SystemSpeechRenderer()
        let job = Task { try await renderer.render("你好，这是合成测试，不包含私人内容。") }
        let timeout = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            job.cancel()
        }
        defer { timeout.cancel() }
        let clip = try await job.value
        let audio = try AVAudioPlayer(data: clip.data)
        precondition(clip.duration > 0 && clip.frameCount > 0)
        precondition(clip.data.count > 44)
        precondition(abs(audio.duration - clip.duration) < 0.001)
        precondition(audio.prepareToPlay() && audio.play())
        while audio.isPlaying {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let canceled = Task { try await renderer.render("取消检查，不播放。") }
        canceled.cancel()
        do {
            _ = try await canceled.value
            preconditionFailure("已取消请求仍返回音频")
        } catch is CancellationError { }
        print("系统音频检查通过：真实内存 WAV 可解码、帧数／时长一致并完成播放；不落音频文件")
    }
}
