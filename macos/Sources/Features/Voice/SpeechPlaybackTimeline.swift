import Foundation

struct SpeechPlaybackTimeline {
    let durations: [TimeInterval]
    let starts: [TimeInterval]
    let total: TimeInterval

    init(durations: [TimeInterval]) throws {
        guard !durations.isEmpty, durations.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var starts: [TimeInterval] = []
        var total: TimeInterval = 0
        for duration in durations { starts.append(total); total += duration }
        guard total.isFinite else { throw CocoaError(.fileReadCorruptFile) }
        self.durations = durations
        self.starts = starts
        self.total = total
    }

    func location(at seconds: TimeInterval) -> (index: Int, offset: TimeInterval)? {
        guard seconds.isFinite else { return nil }
        let time = max(0, min(seconds, total))
        let index = starts.lastIndex(where: { $0 <= time }) ?? 0
        return (index, min(time - starts[index], durations[index]))
    }
}
