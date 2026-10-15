import Foundation

/// 一次语义朗读记录。
struct VoiceHistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    var summary: String?
    var createdAt: Date
    var segments: [SpeechSegment]
    var wasRewritten: Bool?
    var projectName: String?
    var terminalTitle: String?
    var originalSourceID: String?
    var hasRecordedAudio: Bool { !segments.isEmpty && segments.allSatisfy { $0.fileName != nil } }
    var totalDuration: TimeInterval { segments.compactMap(\.endTime).max() ?? 0 }
    var displaySummary: String { summary ?? text }

    init(id: UUID = UUID(), text: String, summary: String? = nil, createdAt: Date = .now, segments: [SpeechSegment] = [],
         wasRewritten: Bool? = nil, projectName: String? = nil, terminalTitle: String? = nil,
         originalSourceID: String? = nil) {
        self.id = id
        self.text = text
        self.summary = summary
        self.createdAt = createdAt
        self.segments = segments
        self.wasRewritten = wasRewritten
        self.projectName = projectName
        self.terminalTitle = terminalTitle
        self.originalSourceID = originalSourceID
    }
}
