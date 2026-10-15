import AVFoundation
import Foundation

/// 原包 meta.json 格式，与恢复版索引分开，只读取、不迁移或清理。
enum OriginalVoiceHistoryReader {
    struct Segment: Decodable, Sendable {
        let index: Int
        let text: String
        let fileName: String
        let duration: Double
    }
    struct Record: Decodable, Identifiable, Sendable {
        let id: String
        let createdAt: Date
        let summary: String
        let projectName: String?
        let terminalTitle: String?
        let totalDuration: Double
        let segments: [Segment]
        let wasRewritten: Bool?
    }
    struct Recording: Identifiable, Sendable {
        let record: Record
        let directory: URL
        var id: String { record.id }
    }
    struct Scan: Sendable {
        let recordings: [Recording]
        let unreadableCount: Int
    }

    static var originalRoot: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.mitchellh.ghostty.pro-cn/VoiceHistory", isDirectory: true)
    }

    static func scan(root: URL) throws -> Scan {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return Scan(recordings: [], unreadableCount: 0) }
        let expectedRoot = root.standardizedFileURL
        guard expectedRoot.resolvingSymlinksInPath().standardizedFileURL.path == expectedRoot.path else {
            throw CocoaError(.fileReadNoPermission)
        }
        let children = try manager.contentsOfDirectory(at: expectedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var recordings: [Recording] = []
        var unreadable = 0
        for directory in children {
            do {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true else { continue }
                guard values.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
                let file = directory.appendingPathComponent("meta.json")
                let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                      let size = properties.fileSize, size <= 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let record = try decoder.decode(Record.self, from: Data(contentsOf: file))
                guard record.id == directory.lastPathComponent, !record.id.isEmpty,
                      record.totalDuration.isFinite, record.totalDuration > 0,
                      !record.segments.isEmpty,
                      Set(record.segments.map(\.index)).count == record.segments.count,
                      record.segments.allSatisfy({ $0.index >= 0 && $0.duration.isFinite && $0.duration > 0 }) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                recordings.append(Recording(record: record, directory: directory.standardizedFileURL))
            } catch { unreadable += 1 }
        }
        return Scan(recordings: recordings.sorted { $0.record.createdAt > $1.record.createdAt }, unreadableCount: unreadable)
    }

    static func audio(_ recording: Recording) throws -> [SpeechAudioSegment] {
        let directory = recording.directory.standardizedFileURL
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.path else {
            throw CocoaError(.fileReadNoPermission)
        }
        var loadedBytes = 0
        return try recording.record.segments.sorted { $0.index < $1.index }.map { segment in
            let name = segment.fileName
            guard !name.isEmpty, name == (name as NSString).lastPathComponent, name != ".", name != ".." else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let file = directory.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 64 * 1024 * 1024,
                  loadedBytes <= 512 * 1024 * 1024 - size else { throw CocoaError(.fileReadTooLarge) }
            loadedBytes += size
            let data = try Data(contentsOf: file)
            let player = try AVAudioPlayer(data: data)
            let decoded = try AVAudioFile(forReading: file)
            guard player.duration.isFinite, player.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            return SpeechAudioSegment(text: segment.text,
                audio: RenderedSpeechClip(data: data, duration: player.duration, frameCount: decoded.length))
        }
    }
}
