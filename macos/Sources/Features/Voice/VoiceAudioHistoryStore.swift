import AVFoundation
import Foundation

/// 音频与索引成套保存；原版数据导入另行取证，不覆盖原包目录。
final class VoiceAudioHistoryStore {
    struct PruneResult {
        let entries: [VoiceHistoryEntry]
        let trashLocations: [URL]
    }
    private let root: URL
    private let index: VoiceHistoryStore

    init(indexURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = indexURL ?? support.appendingPathComponent("Ghostty-Recovered/voice-history.json")
        index = VoiceHistoryStore(fileURL: url)
        root = url.deletingLastPathComponent().appendingPathComponent("voice-audio")
    }

    func save(_ clips: [SpeechAudioSegment], summary: String? = nil, wasRewritten: Bool = false,
              projectName: String? = nil, terminalTitle: String? = nil) throws -> [VoiceHistoryEntry] {
        try index.withExclusiveAccess {
            try saveUnlocked(clips, summary: summary, wasRewritten: wasRewritten,
                             projectName: projectName, terminalTitle: terminalTitle)
        }
    }

    func importOriginal(_ recording: OriginalVoiceHistoryReader.Recording) throws -> [VoiceHistoryEntry] {
        try index.withExclusiveAccess {
            let entries = try index.load()
            if let imported = entries.first(where: { $0.originalSourceID == recording.id }) {
                let originalText = recording.record.segments.sorted { $0.index < $1.index }
                    .map(\.text).joined(separator: "\n")
                guard imported.createdAt == recording.record.createdAt,
                      imported.summary == recording.record.summary,
                      imported.text == originalText else { throw CocoaError(.fileReadCorruptFile) }
                return entries
            }
            let clips = try OriginalVoiceHistoryReader.audio(recording)
            return try saveUnlocked(clips, summary: recording.record.summary,
                wasRewritten: recording.record.wasRewritten ?? false,
                projectName: recording.record.projectName, terminalTitle: recording.record.terminalTitle,
                createdAt: recording.record.createdAt, originalSourceID: recording.id, existingEntries: entries)
        }
    }

    private func saveUnlocked(_ clips: [SpeechAudioSegment], summary: String?, wasRewritten: Bool,
                              projectName: String?, terminalTitle: String?, createdAt: Date = .now,
                              originalSourceID: String? = nil,
                              existingEntries: [VoiceHistoryEntry]? = nil) throws -> [VoiceHistoryEntry] {
        guard !clips.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let manager = FileManager.default
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString)
        let staging = root.appendingPathComponent(".pending-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard root.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var excludedRoot = root
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try excludedRoot.setResourceValues(resources)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var committed = false
        defer {
            if !committed {
                try? manager.removeItem(at: staging)
                try? manager.removeItem(at: directory)
            }
        }
        var segments: [SpeechSegment] = []
        var elapsed: TimeInterval = 0
        for (position, clip) in clips.enumerated() {
            guard clip.audio.duration.isFinite, clip.audio.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let decoded = try AVAudioPlayer(data: clip.audio.data)
            guard abs(decoded.duration - clip.audio.duration) < 0.01 else { throw CocoaError(.fileReadCorruptFile) }
            let name = String(format: "segment-%04d", position) + "." + clip.audio.fileExtension
            let file = staging.appendingPathComponent(name)
            try clip.audio.data.write(to: file, options: [.withoutOverwriting])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            segments.append(SpeechSegment(text: clip.text, startTime: elapsed,
                                          endTime: elapsed + clip.audio.duration, fileName: name))
            elapsed += clip.audio.duration
        }
        let entry = VoiceHistoryEntry(id: id, text: clips.map(\.text).joined(separator: "\n"), summary: summary,
                                      createdAt: createdAt,
                                      segments: segments, wasRewritten: wasRewritten,
                                      projectName: projectName, terminalTitle: terminalTitle,
                                      originalSourceID: originalSourceID)
        try saveSnapshot(entry, in: staging)
        try manager.moveItem(at: staging, to: directory)
        var entries = try existingEntries ?? index.load()
        entries.insert(entry, at: 0)
        entries = entries.enumerated().sorted {
            $0.element.createdAt == $1.element.createdAt ? $0.offset < $1.offset :
                $0.element.createdAt > $1.element.createdAt
        }.map(\.element)
        try index.saveUnlocked(entries)
        committed = true
        return entries
    }

    func load(_ entry: VoiceHistoryEntry) throws -> [SpeechAudioSegment] {
        guard entry.hasRecordedAudio else { throw CocoaError(.fileReadNoSuchFile) }
        let directory = root.appendingPathComponent(entry.id.uuidString).standardizedFileURL
        guard directory.resolvingSymlinksInPath() == directory else { throw CocoaError(.fileReadNoPermission) }
        return try entry.segments.map { segment in
            guard let name = segment.fileName, name == (name as NSString).lastPathComponent,
                  name.hasPrefix("segment-"), ["wav", "mp3", "m4a", "audio"].contains((name as NSString).pathExtension) else { throw CocoaError(.fileReadInvalidFileName) }
            let file = directory.appendingPathComponent(name)
            let properties = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard file.resolvingSymlinksInPath() == file, properties.isRegularFile == true,
                  let size = properties.fileSize, size <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let data = try Data(contentsOf: file)
            let audio = try AVAudioPlayer(data: data)
            let decodedFile = try AVAudioFile(forReading: file)
            guard audio.duration.isFinite, audio.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            return SpeechAudioSegment(text: segment.text, audio: RenderedSpeechClip(data: data, duration: audio.duration, frameCount: decodedFile.length))
        }
    }

    func retentionPlan(maxCount: Int = VoiceHistoryRetention.defaultCount,
                       maxBytes: Int64 = VoiceHistoryRetention.defaultBytes) throws -> [UUID] {
        let items = try index.load().filter(\.hasRecordedAudio).map { entry in
            VoiceHistoryRetention.Item(id: entry.id, createdAt: entry.createdAt,
                                       bytes: try directoryBytes(entry.id))
        }
        return try VoiceHistoryRetention.removals(items, maxCount: maxCount, maxBytes: maxBytes)
    }

    func totalBytes() throws -> Int64 {
        try index.load().filter(\.hasRecordedAudio).reduce(into: 0) { total, entry in
            let sum = total.addingReportingOverflow(try directoryBytes(entry.id))
            guard !sum.overflow else { throw CocoaError(.fileReadTooLarge) }
            total = sum.partialValue
        }
    }

    func recordingURL(for entry: VoiceHistoryEntry) -> URL? {
        guard entry.hasRecordedAudio else { return nil }
        let directory = root.appendingPathComponent(entry.id.uuidString).standardizedFileURL
        guard root.resolvingSymlinksInPath().standardizedFileURL == root.standardizedFileURL,
              directory.resolvingSymlinksInPath() == directory,
              (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return directory
    }

    /// 只处理本恢复版完整录音；目录先进入废纸篓，索引失败则移回。
    func trash(_ ids: Set<UUID>) throws -> PruneResult {
        try index.withExclusiveAccess {
            let entries = try index.load()
            let recorded = Set(entries.filter(\.hasRecordedAudio).map(\.id))
            guard ids.isSubset(of: recorded) else { throw CocoaError(.fileWriteNoPermission) }
            return try trashUnlocked(entries: entries, ids: entries.map(\.id).filter(ids.contains))
        }
    }

    /// 已获用户批准的回收站策略；原包目录不在本存储根目录范围内。
    func enforceLimits(maxCount: Int = VoiceHistoryRetention.defaultCount,
                       maxBytes: Int64 = VoiceHistoryRetention.defaultBytes) throws -> PruneResult {
        try index.withExclusiveAccess {
            let entries = try index.load()
            return try trashUnlocked(entries: entries,
                                     ids: try retentionPlan(maxCount: maxCount, maxBytes: maxBytes))
        }
    }

    private func trashUnlocked(entries: [VoiceHistoryEntry], ids: [UUID]) throws -> PruneResult {
        guard !ids.isEmpty else { return PruneResult(entries: entries, trashLocations: []) }
        let manager = FileManager.default
        var moved: [(source: URL, trash: URL)] = []
        do {
            for id in ids {
                let source = root.appendingPathComponent(id.uuidString).standardizedFileURL
                guard root.resolvingSymlinksInPath().standardizedFileURL == root.standardizedFileURL,
                      source.resolvingSymlinksInPath() == source,
                      try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                      let entry = entries.first(where: { $0.id == id }) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                if !manager.fileExists(atPath: source.appendingPathComponent("record.json").path) {
                    try saveSnapshot(entry, in: source)
                }
                var resulting: NSURL?
                try manager.trashItem(at: source, resultingItemURL: &resulting)
                guard let trash = resulting as URL? else {
                    throw NSError(domain: "Ghostty.AudioHistory", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "录音已移到回收站，但无法取得恢复路径；索引未更新"])
                }
                moved.append((source, trash))
            }
            let removed = Set(ids)
            let retained = entries.filter { !removed.contains($0.id) }
            try index.saveUnlocked(retained)
            return PruneResult(entries: retained, trashLocations: moved.map(\.trash))
        } catch {
            var failedRestore = false
            for item in moved.reversed() {
                do { try manager.moveItem(at: item.trash, to: item.source) }
                catch { failedRestore = true }
            }
            if failedRestore {
                throw NSError(domain: "Ghostty.AudioHistory", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "清理未完成，部分录音仍在回收站，可手动找回；原索引保留"])
            }
            throw error
        }
    }

    private func directoryBytes(_ id: UUID) throws -> Int64 {
        let directory = root.appendingPathComponent(id.uuidString).standardizedFileURL
        guard directory.resolvingSymlinksInPath() == directory else { throw CocoaError(.fileReadNoPermission) }
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        var total: Int64 = 0
        for file in files {
            guard file.resolvingSymlinksInPath().standardizedFileURL == file.standardizedFileURL else {
                throw CocoaError(.fileReadNoPermission)
            }
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  let size = values.fileSize else { throw CocoaError(.fileReadCorruptFile) }
            let sum = total.addingReportingOverflow(Int64(size))
            guard !sum.overflow else { throw CocoaError(.fileReadTooLarge) }
            total = sum.partialValue
        }
        return total
    }

    private func saveSnapshot(_ entry: VoiceHistoryEntry, in directory: URL) throws {
        var protectedDirectory = directory
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(resources)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("record.json")
        try encoder.encode(entry).write(to: file, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// 用户从回收站找回录音后明确刷新，恢复目录内完整快照重新加入索引。
    func restoreIndex() throws -> [VoiceHistoryEntry] {
        try index.withExclusiveAccess {
            var entries = try index.load()
            var known = Set(entries.map(\.id))
            guard FileManager.default.fileExists(atPath: root.path) else { return entries }
            let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            var changed = false
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for directory in directories {
                guard let id = UUID(uuidString: directory.lastPathComponent), !known.contains(id) else { continue }
                let snapshot = directory.appendingPathComponent("record.json")
                guard directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL,
                      snapshot.resolvingSymlinksInPath().standardizedFileURL == snapshot.standardizedFileURL else {
                    throw CocoaError(.fileReadNoPermission)
                }
                let values = try snapshot.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size <= 1024 * 1024 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let entry = try decoder.decode(VoiceHistoryEntry.self, from: Data(contentsOf: snapshot))
                guard entry.id == id, entry.hasRecordedAudio else { throw CocoaError(.fileReadCorruptFile) }
                _ = try load(entry)
                entries.append(entry)
                known.insert(id)
                changed = true
            }
            if changed {
                entries = entries.enumerated().sorted {
                    $0.element.createdAt == $1.element.createdAt ? $0.offset < $1.offset : $0.element.createdAt > $1.element.createdAt
                }.map(\.element)
                try index.saveUnlocked(entries)
            }
            return entries
        }
    }
}
