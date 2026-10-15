import AVFoundation
import Foundation

struct RenderedSpeechClip: Sendable {
    let data: Data
    let duration: TimeInterval
    let frameCount: Int64
    var fileExtension: String {
        if data.starts(with: Data("RIFF".utf8)), data.count >= 12,
           data[8..<12] == Data("WAVE".utf8) { return "wav" }
        if data.count >= 8, data[4..<8] == Data("ftyp".utf8) { return "m4a" }
        if data.starts(with: Data("ID3".utf8)) || (data.count >= 2 && data[0] == 0xff && data[1] & 0xe0 == 0xe0) { return "mp3" }
        return "audio"
    }
}

/// 生成真实系统语音音频，不通过文字长度估算时长。
@MainActor
final class SystemSpeechRenderer {
    enum RenderError: LocalizedError {
        case empty
        var errorDescription: String? { "没有可以合成的文字" }
    }
    private let synth = AVSpeechSynthesizer()
    private var pending: Pending?

    func render(_ text: String, voiceIdentifier: String? = nil) async throws -> RenderedSpeechClip {
        cancel()
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RenderError.empty }
        let request = Pending()
        pending = request
        defer {
            if pending === request {
                pending = nil
                synth.stopSpeaking(at: .immediate)
            }
        }
        let clip = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.begin(continuation)
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
                    ?? SystemVoiceCatalog.preferredChineseVoice()
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                synth.write(utterance) { buffer in request.consume(buffer) }
            }
        } onCancel: {
            request.cancel()
            Task { @MainActor [weak self] in
                guard self?.pending === request else { return }
                self?.synth.stopSpeaking(at: .immediate)
            }
        }
        try Task.checkCancellation()
        return clip
    }

    func cancel() {
        let request = pending
        pending = nil
        request?.cancel()
        synth.stopSpeaking(at: .immediate)
    }

    /// AVFoundation 回调同步消费音频缓冲区，避免跨队列后缓冲区已被复用。
    private final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var converter: AVAudioConverter?
        private var outputFormat: AVAudioFormat?
        private var pcmData = Data()
        private var frames: Int64 = 0
        private var sampleRate: Double = 0
        private var continuation: CheckedContinuation<RenderedSpeechClip, Error>?
        private var finished = false

        func begin(_ value: CheckedContinuation<RenderedSpeechClip, Error>) {
            lock.lock()
            defer { lock.unlock() }
            if finished { value.resume(throwing: CancellationError()) }
            else { continuation = value }
        }

        func consume(_ buffer: AVAudioBuffer) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                finish(.failure(CocoaError(.fileReadCorruptFile)))
                return
            }
            do {
                if pcm.frameLength == 0 {
                    guard frames > 0, sampleRate > 0 else { throw CocoaError(.fileReadCorruptFile) }
                    finish(.success(RenderedSpeechClip(data: try waveData(), duration: Double(frames) / sampleRate, frameCount: frames)))
                    return
                }
                if converter == nil {
                    guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: pcm.format.sampleRate,
                                                     channels: pcm.format.channelCount, interleaved: true),
                          let conversion = AVAudioConverter(from: pcm.format, to: format) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    outputFormat = format
                    converter = conversion
                    sampleRate = pcm.format.sampleRate
                }
                guard sampleRate == pcm.format.sampleRate, let outputFormat,
                      outputFormat.channelCount == pcm.format.channelCount,
                      let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: pcm.frameLength) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try converter?.convert(to: converted, from: pcm)
                let buffer = converted.audioBufferList.pointee.mBuffers
                guard let bytes = buffer.mData, pcmData.count + Int(buffer.mDataByteSize) <= 64 * 1024 * 1024 else {
                    throw CocoaError(.fileReadTooLarge)
                }
                pcmData.append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(buffer.mDataByteSize))
                frames += Int64(converted.frameLength)
            } catch { finish(.failure(error)) }
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finish(.failure(CancellationError()))
        }

        private func finish(_ result: Result<RenderedSpeechClip, Error>) {
            finished = true
            converter = nil
            pcmData.removeAll()
            let callback = continuation
            continuation = nil
            callback?.resume(with: result)
        }

        private func waveData() throws -> Data {
            guard let outputFormat, sampleRate <= Double(UInt32.max),
                  outputFormat.channelCount <= 32 else { throw CocoaError(.fileReadCorruptFile) }
            let channels = UInt16(outputFormat.channelCount)
            guard channels > 0, sampleRate > 0,
                  sampleRate <= Double(UInt32.max / UInt32(channels * 2)) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let rate = UInt32(sampleRate)
            var data = Data("RIFF".utf8)
            func append<T: FixedWidthInteger>(_ value: T) {
                var little = value.littleEndian
                withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
            }
            append(UInt32(pcmData.count + 36))
            data.append(Data("WAVEfmt ".utf8))
            append(UInt32(16)); append(UInt16(1)); append(channels)
            append(rate); append(rate * UInt32(channels) * 2)
            append(channels * 2); append(UInt16(16))
            data.append(Data("data".utf8)); append(UInt32(pcmData.count))
            data.append(pcmData)
            return data
        }
    }
}
