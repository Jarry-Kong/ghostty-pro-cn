import Foundation

@main
enum OriginalHistoryCheck {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Ghostty-Original-History-Test-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let id = "20261006-080000"
        let directory = root.appendingPathComponent(id)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        let renderer = SystemSpeechRenderer()
        let job = Task { try await renderer.render("原版格式兼容检查，只有合成短句。") }
        let timeout = Task { try await Task.sleep(nanoseconds: 30_000_000_000); job.cancel() }
        defer { timeout.cancel() }
        let clip = try await job.value
        let audioFile = directory.appendingPathComponent("0000.wav")
        try clip.data.write(to: audioFile)
        let value: [String: Any] = ["id": id, "createdAt": "2026-10-06T00:00:00Z", "summary": "合成检查",
            "totalDuration": clip.duration, "wasRewritten": false,
            "segments": [["index": 0, "text": "合成短句", "fileName": "0000.wav", "duration": clip.duration]]]
        let metadata = try JSONSerialization.data(withJSONObject: value)
        let file = directory.appendingPathComponent("meta.json")
        try metadata.write(to: file)
        let broken = root.appendingPathComponent("broken")
        try manager.createDirectory(at: broken, withIntermediateDirectories: false)
        try Data("损坏".utf8).write(to: broken.appendingPathComponent("meta.json"))
        let result = try OriginalVoiceHistoryReader.scan(root: root)
        precondition(result.recordings.count == 1 && result.unreadableCount == 1)
        let audio = try OriginalVoiceHistoryReader.audio(result.recordings[0])
        precondition(audio.count == 1 && audio[0].audio.data == clip.data)
        let preserved = try Data(contentsOf: file)
        precondition(preserved == metadata)
        let unsafeRecord = OriginalVoiceHistoryReader.Record(id: id, createdAt: Date(), summary: "越界样例",
            projectName: nil, terminalTitle: nil, totalDuration: clip.duration,
            segments: [.init(index: 0, text: "样例", fileName: "../outside.wav", duration: clip.duration)], wasRewritten: nil)
        do {
            _ = try OriginalVoiceHistoryReader.audio(.init(record: unsafeRecord, directory: directory))
            preconditionFailure("路径越界未拒绝")
        } catch { }
        print("原版格式检查通过：非 UUID 编号、meta.json／ISO 日期、真实音频读取、损坏项计数与元数据不变；仅合成副本")
    }
}
