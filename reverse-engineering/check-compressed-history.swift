import Foundation
import AVFoundation

@main
enum CheckCompressedHistory {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Ghostty-Compressed-Test-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent("synthetic.m4a")
        var writer: AVAudioFile? = try AVAudioFile(forWriting: file, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000.0,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: writer!.processingFormat, frameCapacity: 6000)!
        buffer.frameLength = 6000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 6000)
        try writer!.write(from: buffer)
        writer = nil
        let data = try Data(contentsOf: file)
        let duration = try SpeechPlayer.validatedDuration(of: data)
        let clip = RenderedSpeechClip(data: data, duration: duration, frameCount: 0)
        precondition(clip.fileExtension == "m4a" && duration > 0)
        let store = VoiceAudioHistoryStore(indexURL: root.appendingPathComponent("history.json"))
        let entries = try store.save([SpeechAudioSegment(text: "合成静音压缩录音", audio: clip)], wasRewritten: true)
        precondition(entries[0].segments[0].fileName?.hasSuffix(".m4a") == true && entries[0].wasRewritten == true)
        let loaded = try store.load(entries[0])
        precondition(loaded[0].audio.data == data && abs(loaded[0].audio.duration - duration) < 0.001)
        precondition(loaded[0].audio.frameCount > 0)
        let reloaded = try VoiceHistoryStore(fileURL: root.appendingPathComponent("history.json")).load()
        precondition(reloaded.first?.wasRewritten == true)
        // 十个独立的 MPEG-1 Layer III 帧，零系数；是否有效由系统解码器决定。
        var mp3 = Data()
        for _ in 0..<10 { mp3.append(Data([0xff, 0xfb, 0x90, 0x00])); mp3.append(Data(repeating: 0, count: 413)) }
        let mp3Duration = try SpeechPlayer.validatedDuration(of: mp3)
        let mp3Clip = RenderedSpeechClip(data: mp3, duration: mp3Duration, frameCount: 0)
        precondition(mp3Clip.fileExtension == "mp3")
        let mp3Entries = try store.save([SpeechAudioSegment(text: "合成静音 MP3", audio: mp3Clip)])
        precondition(mp3Entries[0].segments[0].fileName?.hasSuffix(".mp3") == true)
        let mp3Loaded = try store.load(mp3Entries[0])
        precondition(mp3Loaded[0].audio.data == mp3 && abs(mp3Loaded[0].audio.duration - mp3Duration) < 0.001)
        precondition(mp3Loaded[0].audio.frameCount > 0)
        try manager.removeItem(at: root)
        precondition(!manager.fileExists(atPath: root.path))
        print("M4A／MP3 实际解码历史检查通过：原生解码准备、扩展名、保存／重载、读取帧数及改写标记；仅临时静音数据，未播放，已清理")
    }
}
