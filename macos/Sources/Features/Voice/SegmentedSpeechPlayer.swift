import Combine
import Foundation

struct SpeechAudioSegment: Sendable {
    let text: String
    let audio: RenderedSpeechClip
}

@MainActor
final class SegmentedSpeechPlayer: ObservableObject {
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentIndex = 0
    @Published private(set) var isActive = false
    @Published private(set) var isPaused = false
    @Published private(set) var errorMessage: String?
    var rate: Double = 1 {
        didSet {
            rate = rate.isFinite ? max(0.5, min(2, rate)) : 1
            player.rate = rate
        }
    }
    private let player = SpeechPlayer()
    private var segments: [SpeechAudioSegment] = []
    private var timeline: SpeechPlaybackTimeline?
    private var generation = UUID()

    func play(_ clips: [SpeechAudioSegment], startPaused: Bool = false) throws {
        stop()
        let timeline = try SpeechPlaybackTimeline(durations: clips.map { $0.audio.duration })
        self.timeline = timeline
        segments = clips
        duration = timeline.total
        errorMessage = nil
        try startClip(0, offset: 0, paused: startPaused)
    }

    func togglePause() {
        guard isActive else { return }
        if isPaused {
            player.resume()
            isActive = player.isActive
            isPaused = false
            if !isActive { errorMessage = "无法继续播放音频" }
        } else { player.pause(); isPaused = player.isPaused }
    }

    func seek(to seconds: TimeInterval) throws {
        guard let timeline, let location = timeline.location(at: seconds) else { return }
        if seconds >= timeline.total {
            generation = UUID()
            player.onProgress = nil
            player.onCompletion = nil
            player.stop()
            position = duration
            currentIndex = segments.count - 1
            isActive = false
            isPaused = false
            return
        }
        let paused = isPaused
        // 每次定位更新代次，先前排队的进度与完成事件不能覆盖新位置。
        try startClip(location.index, offset: location.offset, paused: paused)
    }

    func jump(to index: Int) throws {
        guard let timeline, timeline.starts.indices.contains(index) else { return }
        try seek(to: timeline.starts[index])
    }

    func stop() {
        generation = UUID()
        player.onProgress = nil
        player.onCompletion = nil
        player.stop()
        segments.removeAll()
        timeline = nil
        position = 0
        duration = 0
        currentIndex = 0
        isActive = false
        isPaused = false
    }

    private func startClip(_ index: Int, offset: TimeInterval, paused: Bool) throws {
        guard segments.indices.contains(index), let timeline else { return }
        let token = UUID()
        generation = token
        currentIndex = index
        position = timeline.starts[index] + offset
        player.rate = rate
        player.onProgress = { [weak self] time, _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.position = timeline.starts[index] + time
            }
        }
        player.onCompletion = { [weak self] success in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if !success {
                    self.isActive = false
                    self.isPaused = false
                    self.errorMessage = "音频播放失败"
                } else if index + 1 < self.segments.count {
                    do { try self.startClip(index + 1, offset: 0, paused: false) }
                    catch { self.isActive = false; self.errorMessage = error.localizedDescription }
                } else {
                    self.position = self.duration
                    self.isActive = false
                    self.isPaused = false
                }
            }
        }
        do {
            try player.play(data: segments[index].audio.data, at: offset, startPaused: paused)
            isActive = true
            isPaused = paused
        } catch {
            isActive = false
            isPaused = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
