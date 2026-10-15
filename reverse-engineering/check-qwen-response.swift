import Foundation

@main
enum CheckQwenResponse {
    static func main() throws {
        let candidate = String(repeating: "A", count: 513)
        precondition(!QwenTTSResponse.isBase64Candidate(String(candidate.prefix(512)), atPath: "audio"))
        for path in ["OUTPUT.AUDIO", "result.data", "message.content"] {
            precondition(QwenTTSResponse.isBase64Candidate(candidate, atPath: path))
        }
        precondition(!QwenTTSResponse.isBase64Candidate(candidate, atPath: "description"))
        precondition(!QwenTTSResponse.isBase64Candidate("!" + candidate, atPath: "audio"))
        precondition(QwenTTSResponse.isBase64Candidate(String(repeating: "A", count: 64) + "!" + candidate, atPath: "audio"))
        precondition(Data(base64Encoded: String(repeating: "A", count: 64) + "!" + candidate) == nil)
        let address = "https://example.invalid/audio.mp3?signature=synthetic"
        for path in QwenTTSResponse.preferredURLPaths {
            var object: Any = address
            for key in path.reversed() { object = [key: object] }
            let result = QwenTTSResponse.preferredAudioURL(in: object)
            precondition(result?.path == path.joined(separator: "."))
            precondition(result?.url.absoluteString == address)
        }
        let priority: [String: Any] = ["output": ["audio": ["url": address]],
                                       "url": "https://example.invalid/other.mp3"]
        precondition(QwenTTSResponse.preferredAudioURL(in: priority)?.path == "output.audio.url")
        let fallback: [String: Any] = ["output": ["audio": ["url": "file:///tmp/private"]], "url": address]
        precondition(QwenTTSResponse.preferredAudioURL(in: fallback)?.path == "url")
        precondition(QwenTTSResponse.preferredAudioURL(in: ["url": "http://example.invalid/test.mp3"])?.url.scheme == "https")
        for value: Any in ["file:///tmp/private", "https://user:password@example.invalid/x", "https://example.invalid/x#fragment", 123, NSNull()] {
            precondition(QwenTTSResponse.preferredAudioURL(in: ["url": value]) == nil)
        }
        precondition(QwenTTSResponse.preferredAudioURL(in: ["unknown": ["url": address]]) == nil)
        func decode(_ object: [String: Any]) throws -> QwenTTSResponse.Payload {
            try QwenTTSResponse.decode(JSONSerialization.data(withJSONObject: object))
        }
        switch try decode(["items": [["source": address]]]) {
        case let .url(path, url): precondition(path == "items[0].source" && url.absoluteString == address)
        case .bytes: preconditionFailure("嵌套音频地址未提取")
        }
        let raw = Data(repeating: 7, count: 600)
        let statusBody = try JSONSerialization.data(withJSONObject: ["url": address])
        _ = try QwenTTSResponse.decode(statusBody, statusCode: 200)
        for status in [201, 204, 301, 429, 500] {
            do { _ = try QwenTTSResponse.decode(statusBody, statusCode: status); preconditionFailure("错误响应不得当作音频") }
            catch QwenTTSResponse.ResponseError.httpStatus(let actual) { precondition(actual == status) }
        }
        do { _ = try QwenTTSResponse.decode(statusBody, statusCode: 401); preconditionFailure("401 必须提示鉴权失败") }
        catch QwenTTSResponse.ResponseError.unauthorized { }
        do { _ = try QwenTTSResponse.decode(statusBody, statusCode: 403); preconditionFailure("403 必须提示路由拒绝") }
        catch QwenTTSResponse.ResponseError.routeNotAllowed(let route) { precondition(route == "/bailian/audio/tts") }
        switch try decode(["nested": ["audio_data": raw.base64EncodedString()]]) {
        case let .bytes(path, data): precondition(path == "nested.audio_data" && data == raw)
        case .url: preconditionFailure("Base64 未提取")
        }
        switch try decode(["items": [["source": address]], "audio_data": raw.base64EncodedString()]) {
        case .url: break
        case .bytes: preconditionFailure("URL 必须先于 Base64")
        }
        for object: [String: Any] in [
            ["link": "https://example.invalid/not-audio"],
            ["audio_data": String(repeating: "A", count: 64) + "!" + candidate],
            ["audio_data": "短内容"]
        ] {
            do { _ = try decode(object); preconditionFailure("无效载荷必须报错") }
            catch is CocoaError { }
        }
        var deep: Any = "终点"
        for _ in 0..<70 { deep = ["child": deep] }
        do { _ = try decode(["root": deep]); preconditionFailure("过深输入必须报错") }
        catch is CocoaError { }
        print("网关优先 URL 路径离线检查通过：八路径、顺序、非法候选跳过、HTTPS 与签名查询保留；未下载")
    }
}
