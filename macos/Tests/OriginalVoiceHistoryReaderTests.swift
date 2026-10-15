import AVFoundation
import XCTest
@testable import Ghostty

final class OriginalVoiceHistoryReaderTests: XCTestCase {
    func testImportCopiesMetadataAndAudioIdempotentlyWithoutMutatingOriginal() throws {
        let manager = FileManager.default
        let fixtureRoot = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let originalRoot = fixtureRoot.appendingPathComponent("original")
        let source = originalRoot.appendingPathComponent("20261013-120000")
        let recoveredIndex = fixtureRoot.appendingPathComponent("recovered/voice-history.json")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: fixtureRoot) }

        let audioFile = source.appendingPathComponent("0000.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800))
        buffer.frameLength = 800
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 800)
        try AVAudioFile(forWriting: audioFile, settings: format.settings).write(from: buffer)
        let metadata = Data("""
        {"id":"20261013-120000","createdAt":"2026-10-13T04:00:00Z","summary":"原版样例",
         "projectName":"ghostty","terminalTitle":"开发","totalDuration":0.1,"wasRewritten":true,
         "segments":[{"index":0,"text":"第一段","fileName":"0000.wav","duration":0.1}]}
        """.utf8)
        let metadataFile = source.appendingPathComponent("meta.json")
        try metadata.write(to: metadataFile)
        let originalAudio = try Data(contentsOf: audioFile)
        let recording = try XCTUnwrap(OriginalVoiceHistoryReader.scan(root: originalRoot).recordings.first)
        let equalDate = Date(timeIntervalSince1970: 2_000_000_000)
        let existing = [
            VoiceHistoryEntry(text: "已有一", createdAt: equalDate),
            VoiceHistoryEntry(text: "已有二", createdAt: equalDate),
        ]
        try VoiceHistoryStore(fileURL: recoveredIndex).save(existing)
        let store = VoiceAudioHistoryStore(indexURL: recoveredIndex)

        let first = try store.importOriginal(recording)
        let second = try store.importOriginal(recording)

        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(second.count, 3)
        XCTAssertEqual(second.prefix(2).map(\.id), existing.map(\.id))
        let imported = try XCTUnwrap(second.first(where: { $0.originalSourceID == recording.id }))
        XCTAssertEqual(imported.originalSourceID, recording.id)
        XCTAssertEqual(imported.summary, "原版样例")
        XCTAssertEqual(imported.projectName, "ghostty")
        XCTAssertEqual(imported.terminalTitle, "开发")
        XCTAssertEqual(imported.wasRewritten, true)
        XCTAssertEqual(imported.createdAt, recording.record.createdAt)
        XCTAssertEqual(imported.segments.map(\.text), ["第一段"])
        XCTAssertEqual(try Data(contentsOf: metadataFile), metadata)
        XCTAssertEqual(try Data(contentsOf: audioFile), originalAudio)
        XCTAssertEqual(try store.load(imported).count, 1)

        let conflict = OriginalVoiceHistoryReader.Recording(record: .init(
            id: recording.id, createdAt: recording.record.createdAt, summary: "同编号的另一条记录",
            projectName: nil, terminalTitle: nil, totalDuration: 0.1,
            segments: recording.record.segments, wasRewritten: nil), directory: recording.directory)
        XCTAssertThrowsError(try store.importOriginal(conflict))
        XCTAssertEqual(try store.load(imported).count, 1)
        XCTAssertEqual(try VoiceHistoryStore(fileURL: recoveredIndex).load().prefix(2).map(\.id), existing.map(\.id))
        XCTAssertEqual(try Data(contentsOf: metadataFile), metadata)
        XCTAssertEqual(try Data(contentsOf: audioFile), originalAudio)
    }

    func testOriginalMetadataShapeAndReadOnlyFailure() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("20261006-080000")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let data = Data("""
        {"id":"20261006-080000","createdAt":"2026-10-06T00:00:00Z","summary":"合成样例",
         "totalDuration":1,"segments":[{"index":0,"text":"样例","fileName":"0000.wav","duration":1}]}
        """.utf8)
        let file = directory.appendingPathComponent("meta.json")
        try data.write(to: file)
        let result = try OriginalVoiceHistoryReader.scan(root: root)
        XCTAssertEqual(result.recordings.count, 1)
        XCTAssertEqual(result.unreadableCount, 0)
        let recording = try XCTUnwrap(result.recordings.first)
        XCTAssertEqual(recording.id, "20261006-080000")
        XCTAssertThrowsError(try OriginalVoiceHistoryReader.audio(recording))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testRejectsSymlinkRootDuplicateSegmentsAndTraversalWithoutMutation() throws {
        let manager = FileManager.default
        let outside = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rootLink = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: rootLink, withDestinationURL: outside)
        defer {
            try? manager.removeItem(at: rootLink)
            try? manager.removeItem(at: outside)
        }
        XCTAssertThrowsError(try OriginalVoiceHistoryReader.scan(root: rootLink))

        let duplicate = outside.appendingPathComponent("duplicate")
        try manager.createDirectory(at: duplicate, withIntermediateDirectories: true)
        let duplicateData = Data("""
        {"id":"duplicate","createdAt":"2026-10-13T00:00:00Z","summary":"损坏样例",
         "totalDuration":2,"segments":[
           {"index":0,"text":"一","fileName":"0000.wav","duration":1},
           {"index":0,"text":"二","fileName":"0001.wav","duration":1}]}
        """.utf8)
        let duplicateMeta = duplicate.appendingPathComponent("meta.json")
        try duplicateData.write(to: duplicateMeta)

        let traversal = outside.appendingPathComponent("traversal")
        try manager.createDirectory(at: traversal, withIntermediateDirectories: true)
        let traversalData = Data("""
        {"id":"traversal","createdAt":"2026-10-13T00:00:01Z","summary":"越界样例",
         "totalDuration":1,"segments":[{"index":0,"text":"一","fileName":"../outside.wav","duration":1}]}
        """.utf8)
        let traversalMeta = traversal.appendingPathComponent("meta.json")
        try traversalData.write(to: traversalMeta)

        let result = try OriginalVoiceHistoryReader.scan(root: outside)
        XCTAssertEqual(result.unreadableCount, 1)
        let recording = try XCTUnwrap(result.recordings.first)
        XCTAssertThrowsError(try OriginalVoiceHistoryReader.audio(recording))
        XCTAssertEqual(try Data(contentsOf: duplicateMeta), duplicateData)
        XCTAssertEqual(try Data(contentsOf: traversalMeta), traversalData)
    }
}
