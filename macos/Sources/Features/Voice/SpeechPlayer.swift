import AVFoundation
import Foundation

/// 语音音频播放层。
/// 支持安装包符号中确认的本地 Data、远程 URL、暂停、继续、跳转和速率控制。
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onCompletion: ((Bool) -> Void)?
    private(set) var isActive = false
    private(set) var isPaused = false
    var rate: Double = 1.0 {
        didSet { audioPlayer?.rate = Float(rate) }
    }

    var currentTime: TimeInterval { audioPlayer?.currentTime ?? 0 }
    var duration: TimeInterval { audioPlayer?.duration ?? 0 }

    /// 只验证，不调用 play；供网关字节和实际播放共用。
    static func validatedDuration(of data: Data) throws -> TimeInterval {
        try preparedPlayer(data: data).duration
    }

    private static func preparedPlayer(data: Data) throws -> AVAudioPlayer {
        guard !data.isEmpty, data.count <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let player = try AVAudioPlayer(data: data)
        guard player.duration.isFinite, player.duration > 0, player.prepareToPlay() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return player
    }

    func play(data: Data, at time: TimeInterval = 0, startPaused: Bool = false) throws {
        stop(notify: false)
        let player = try Self.preparedPlayer(data: data)
        player.delegate = self
        player.enableRate = true
        player.rate = Float(rate)
        player.currentTime = time.isFinite ? max(0, min(time, player.duration)) : 0
        audioPlayer = player
        isActive = !startPaused && player.play()
        isPaused = startPaused
        guard startPaused || isActive else { audioPlayer = nil; throw CocoaError(.fileReadCorruptFile) }
        if isActive { startProgressTimer() }
        emitProgress()
    }

    func play(remote url: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        try play(data: data)
    }

    func pause() {
        guard audioPlayer != nil, isActive else { return }
        audioPlayer?.pause()
        isPaused = true
    }

    func resume() {
        guard let audioPlayer else { return }
        isActive = audioPlayer.play()
        isPaused = false
        startProgressTimer()
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func seek(to time: TimeInterval) {
        guard time.isFinite else { return }
        audioPlayer?.currentTime = max(0, min(time, duration))
        emitProgress()
    }

    func stop(notify: Bool = true) {
        audioPlayer?.stop()
        audioPlayer = nil
        isActive = false
        isPaused = false
        stopProgressTimer()
        if notify { emitProgress() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        isActive = false
        isPaused = false
        stopProgressTimer()
        emitProgress()
        onCompletion?(flag)
    }

    deinit {
        stopProgressTimer()
    }
}

private extension SpeechPlayer {
    func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.emitProgress()
        }
    }

    func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func emitProgress() {
        onProgress?(currentTime, duration)
    }
}
