import Foundation

private final class OfflineResponse: URLProtocol {
    private static let lock = NSLock()
    private static var stalled = false
    static var startedStall: Bool { lock.lock(); defer { lock.unlock() }; return stalled }
    static func wave() -> Data {
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(Data("RIFF".utf8)); word(UInt32(4036)); data.append(Data("WAVEfmt ".utf8))
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(8000)); word(UInt32(16000))
        word(UInt16(2)); word(UInt16(16)); data.append(Data("data".utf8)); word(UInt32(4000))
        data.append(Data(repeating: 0, count: 4000))
        return data
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url!.path == "/stall" {
            Self.lock.lock(); Self.stalled = true; Self.lock.unlock()
            return
        }
        let body: Data
        if request.url!.path == "/audio.mp3" {
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
            precondition(request.httpMethod == "GET")
            body = Self.wave()
        } else if request.url!.path == "/base64" {
            body = try! JSONSerialization.data(withJSONObject: ["audio_data": Self.wave().base64EncodedString()])
        } else {
            body = Data(#"{"url":"https://other.invalid/audio.mp3"}"#.utf8)
        }
        let status = request.url!.path.contains("unauthorized") ? 401 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                            httpVersion: "HTTP/1.1",
                                                            headerFields: request.url!.path == "/oversize" ? ["Content-Length": "67108865"] : nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
enum CheckQwenClient {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineResponse.self]
        let client = QwenTTSClient(configuration: configuration)
        let stalled = Task {
            try await client.synthesize(endpoint: URL(string: "https://example.invalid/stall")!,
                                        text: "离线测试", voice: "test", token: "synthetic")
        }
        let deadline = Date().addingTimeInterval(3)
        while !OfflineResponse.startedStall && Date() < deadline { await Task.yield() }
        precondition(OfflineResponse.startedStall)
        stalled.cancel()
        do { _ = try await stalled.value; preconditionFailure("进行中请求必须取消") }
        catch is CancellationError { }
        catch let error as URLError { precondition(error.code == .cancelled) }
        do {
            _ = try await client.synthesize(endpoint: URL(string: "https://example.invalid/oversize")!,
                                            text: "离线测试", voice: "test", token: "synthetic")
            preconditionFailure("声明超大响应必须拒绝")
        } catch let error as CocoaError { precondition(error.code == .fileReadTooLarge) }
        let inline = try await client.synthesize(endpoint: URL(string: "https://example.invalid/base64")!,
                                                 text: "离线测试", voice: "test", token: "synthetic")
        precondition(inline.data == OfflineResponse.wave() && abs(inline.duration - 0.25) < 0.001)
        let downloaded = try await client.synthesize(endpoint: URL(string: "https://example.invalid/bailian/audio/tts")!,
                                                     text: "离线测试", voice: "test", token: "synthetic",
                                                     permittedAudioHosts: ["other.invalid"])
        precondition(downloaded.data == OfflineResponse.wave() && abs(downloaded.duration - 0.25) < 0.001)
        do {
            _ = try await client.synthesize(endpoint: URL(string: "https://example.invalid/unauthorized")!,
                                            text: "离线测试", voice: "test", token: "synthetic")
            preconditionFailure("401 必须拒绝")
        } catch QwenTTSResponse.ResponseError.unauthorized { }
        do {
            _ = try await client.synthesize(endpoint: URL(string: "https://example.invalid/bailian/audio/tts")!,
                                            text: "离线测试", voice: "test", token: "synthetic")
            preconditionFailure("未授权主机不得下载")
        } catch let error as URLError { precondition(error.code == .noPermissionsToReadFile) }
        let cancelled = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await client.synthesize(endpoint: URL(string: "https://example.invalid/tts")!,
                                                text: "离线测试", voice: "test", token: "synthetic")
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("已取消请求不得开始") }
        catch is CancellationError { }
        print("网关客户端离线检查通过：Base64／URL 音频链路、下载不带令牌／Cookie、401、未授权主机及取消；全部响应由 URLProtocol 提供，未播放")
    }
}
