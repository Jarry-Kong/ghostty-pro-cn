import AVFoundation

enum SystemVoiceCatalog {
    static func chineseVoices(_ voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> [AVSpeechSynthesisVoice] {
        voices.filter { $0.language.lowercased().hasPrefix("zh") }
    }

    static func preferredChineseVoice(_ voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> AVSpeechSynthesisVoice? {
        let chinese = chineseVoices(voices)
        return chinese.first { $0.quality != .default }
            ?? chinese.first { $0.language.caseInsensitiveCompare("zh-CN") == .orderedSame }
            ?? chinese.first
    }
}
