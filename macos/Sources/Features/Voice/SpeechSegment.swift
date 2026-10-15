import Foundation

/// 一段可播放或可定位的朗读内容。
struct SpeechSegment: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var fileName: String?

    init(id: UUID = UUID(), text: String, startTime: TimeInterval = 0, endTime: TimeInterval? = nil, fileName: String? = nil) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.fileName = fileName
    }

    static func timed(_ clips: [SpeechAudioSegment]) throws -> [SpeechSegment] {
        let timeline = try SpeechPlaybackTimeline(durations: clips.map(\.audio.duration))
        return clips.enumerated().map { index, clip in
            SpeechSegment(text: clip.text, startTime: timeline.starts[index],
                          endTime: timeline.starts[index] + clip.audio.duration)
        }
    }
}
