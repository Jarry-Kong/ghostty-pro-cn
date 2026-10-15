import AVFoundation
import Foundation

@main
enum AudioHistoryCheck {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("Ghostty-History-Test-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let indexURL = directory.appendingPathComponent("history.json")
        let renderer = SystemSpeechRenderer()
        let job = Task { try await renderer.render("音频历史检查，只使用合成短句。") }
        let timeout = Task { try await Task.sleep(nanoseconds: 30_000_000_000); job.cancel() }
        defer { timeout.cancel() }
        let clip = try await job.value
        let store = VoiceAudioHistoryStore(indexURL: indexURL)
        let entries = try store.save([
            SpeechAudioSegment(text: "第一段合成短句", audio: clip),
            SpeechAudioSegment(text: "第二段合成短句", audio: clip),
        ], summary: "合成检查", wasRewritten: true, projectName: "临时项目", terminalTitle: "临时终端")
        precondition(entries.first?.wasRewritten == true)
        precondition(entries.first?.projectName == "临时项目")
        precondition(entries.first?.terminalTitle == "临时终端")
        precondition(entries.first?.summary == "合成检查")
        let legacy = try JSONDecoder().decode(VoiceHistoryEntry.self, from: JSONEncoder().encode(VoiceHistoryEntry(text: "旧格式合成记录")))
        precondition(legacy.wasRewritten == nil)
        precondition(legacy.summary == nil && legacy.displaySummary == "旧格式合成记录")
        precondition(entries.count == 1 && entries[0].hasRecordedAudio)
        precondition(entries[0].segments.count == 2)
        precondition(entries[0].segments[0].text == "第一段合成短句")
        precondition(entries[0].segments[0].fileName == "segment-0000.wav")
        precondition(entries[0].segments[0].startTime == 0)
        precondition(abs((entries[0].segments[0].endTime ?? 0) - clip.duration) < 0.001)
        precondition(entries[0].segments[1].text == "第二段合成短句")
        precondition(entries[0].segments[1].fileName == "segment-0001.wav")
        precondition(abs(entries[0].segments[1].startTime - clip.duration) < 0.001)
        precondition(abs((entries[0].segments[1].endTime ?? 0) - clip.duration * 2) < 0.001)
        let reloaded = try VoiceHistoryStore(fileURL: indexURL).load()
        precondition(reloaded.first?.wasRewritten == true)
        precondition(reloaded.first?.projectName == "临时项目")
        precondition(reloaded.first?.terminalTitle == "临时终端")
        precondition(reloaded.first?.summary == "合成检查")
        let clips = try VoiceAudioHistoryStore(indexURL: indexURL).load(reloaded[0])
        precondition(clips.map(\.text) == ["第一段合成短句", "第二段合成短句"])
        precondition(clips.allSatisfy { $0.audio.data == clip.data })
        precondition(clips.allSatisfy { abs($0.audio.duration - clip.duration) < 0.001 })
        let initialBytes = try store.totalBytes()
        precondition(initialBytes > Int64(clip.data.count * 2))
        let player = SegmentedSpeechPlayer()
        try player.play(clips, startPaused: true)
        try player.jump(to: 1)
        precondition(player.currentIndex == 1)
        precondition(abs(player.position - clip.duration) < 0.001)
        precondition(player.isPaused)
        player.stop()
        let permissions = try manager.attributesOfItem(atPath: indexURL.path)[.posixPermissions] as? Int
        precondition(permissions == 0o600)
        let audioRoot = directory.appendingPathComponent("voice-audio")
        let resources = try audioRoot.resourceValues(forKeys: [.isExcludedFromBackupKey])
        precondition(resources.isExcludedFromBackup == true)
        let newer = try store.save([SpeechAudioSegment(text: "第二份测试录音", audio: clip)])
        let plan = try store.retentionPlan(maxCount: 1, maxBytes: Int64.max)
        precondition(plan == [entries[0].id])
        print("临时录音及清理计划验证完成，下一步调用回收站")
        let pruned = try store.enforceLimits(maxCount: 1, maxBytes: Int64.max)
        precondition(pruned.entries.count == 1 && pruned.entries[0].id == newer[0].id)
        precondition(pruned.trashLocations.count == 1)
        let trash = pruned.trashLocations[0]
        let trashResources = try trash.resourceValues(forKeys: [.isExcludedFromBackupKey])
        precondition(trashResources.isExcludedFromBackup == true)
        precondition(manager.fileExists(atPath: trash.appendingPathComponent("record.json").path))
        let originalDirectory = audioRoot.appendingPathComponent(entries[0].id.uuidString)
        precondition(!manager.fileExists(atPath: originalDirectory.path))
        try manager.moveItem(at: trash, to: originalDirectory)
        precondition(manager.fileExists(atPath: originalDirectory.appendingPathComponent("segment-0000.wav").path))
        let restoredEntries = try store.restoreIndex()
        precondition(restoredEntries.count == 2 && restoredEntries.contains { $0.id == entries[0].id })
        let restoredAgain = try store.restoreIndex()
        precondition(restoredAgain.count == 2)
        let third = try store.save([SpeechAudioSegment(text: "单条删除检查", audio: clip)])[0]
        precondition(store.recordingURL(for: third)?.lastPathComponent == third.id.uuidString)
        let removedOne = try store.trash([third.id])
        precondition(!removedOne.entries.contains { $0.id == third.id })
        precondition(removedOne.trashLocations.count == 1)
        try manager.moveItem(at: removedOne.trashLocations[0], to: audioRoot.appendingPathComponent(third.id.uuidString))
        let restoredThird = try store.restoreIndex()
        precondition(restoredThird.contains { $0.id == third.id })
        let beforeClear = try VoiceHistoryStore(fileURL: indexURL).load()
        let cleared = try store.trash(Set(beforeClear.map(\.id)))
        precondition(cleared.entries.isEmpty && cleared.trashLocations.count == beforeClear.count)
        let clearedBytes = try store.totalBytes()
        precondition(clearedBytes == 0)
        let snapshotDecoder = JSONDecoder()
        snapshotDecoder.dateDecodingStrategy = .iso8601
        for location in cleared.trashLocations {
            let record = try snapshotDecoder.decode(VoiceHistoryEntry.self,
                from: Data(contentsOf: location.appendingPathComponent("record.json")))
            try manager.moveItem(at: location, to: audioRoot.appendingPathComponent(record.id.uuidString))
        }
        let restoredAfterClear = try store.restoreIndex()
        precondition(restoredAfterClear.count == beforeClear.count)
        let restoredBytes = try store.totalBytes()
        precondition(restoredBytes > 0)
        let indexBeforeFailure = try Data(contentsOf: indexURL)
        try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        do {
            _ = try store.enforceLimits(maxCount: 0, maxBytes: Int64.max)
            preconditionFailure("只读索引目录未触发失败")
        } catch { }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let indexAfterFailure = try Data(contentsOf: indexURL)
        precondition(indexBeforeFailure == indexAfterFailure)
        precondition(manager.fileExists(atPath: audioRoot.appendingPathComponent(newer[0].id.uuidString).path))
        let indexStore = VoiceHistoryStore(fileURL: indexURL)
        try indexStore.withExclusiveAccess {
            do {
                try indexStore.save(pruned.entries)
                preconditionFailure("同进程重入写锁未被拒绝")
            } catch { }
        }
        let file = audioRoot.appendingPathComponent(entries[0].id.uuidString).appendingPathComponent("segment-0000.wav")
        try manager.removeItem(at: file)
        do { _ = try store.load(entries[0]); preconditionFailure("缺音频没有报错") } catch { }
        let preservedIndex = try Data(contentsOf: indexURL)
        precondition(preservedIndex.count > 0)
        print("音频历史检查通过：两段映射与暂停态跳段、磁盘占用统计、单条／全部移入回收站并找回、真实保存／重载、权限／不备份、限额清理、快照保留及缺文件报错；测试录音已恢复到临时目录并清理")
    }
}
