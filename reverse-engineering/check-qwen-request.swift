import Foundation

@main
enum CheckQwenRequest {
    static func main() throws {
        precondition(QwenTTSRequest.timeout(characterCount: 0) == 30)
        precondition(QwenTTSRequest.timeout(characterCount: 100) == 38)
        precondition(QwenTTSRequest.timeout(characterCount: 1875) == 180)
        precondition(QwenTTSRequest.timeout(characterCount: Int.max) == 180)
        let endpoint = URL(string: "https://example.invalid/bailian/audio/tts")!
        for base in ["https://example.invalid", " https://example.invalid/// "] {
            let resolved = try QwenTTSRequest.endpoint(baseURL: base)
            precondition(resolved == endpoint)
        }
        let prefixed = try QwenTTSRequest.endpoint(baseURL: "https://example.invalid/gateway/")
        precondition(prefixed.path == "/gateway/bailian/audio/tts")
        for base in ["", "http://example.invalid", "https://example.invalid?token=secret",
                     "https://user:secret@example.invalid", "https://example.invalid\n"] {
            do { _ = try QwenTTSRequest.endpoint(baseURL: base); preconditionFailure("不安全基础地址必须拒绝") }
            catch is URLError { }
        }
        let request = try QwenTTSRequest.make(endpoint: endpoint, text: "离线合成测试", voice: "test-voice",
                                              token: "synthetic-token", timeout: 60)
        precondition(request.url == endpoint && request.httpMethod == "POST")
        let unicode = try QwenTTSRequest.make(endpoint: endpoint, text: " 👨‍👩‍👧‍👦 ", voice: "test", token: "test")
        precondition(abs(unicode.timeoutInterval - 30.08) < 0.000001)
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(Set(body.keys) == Set(["model", "input"]))
        precondition(body["model"] as? String == QwenTTSRequest.defaultModel)
        let input = body["input"] as! [String: Any]
        precondition(Set(input.keys) == Set(["text", "voice", "format", "sample_rate", "rate"]))
        precondition(input["text"] as? String == "离线合成测试" && input["voice"] as? String == "test-voice")
        precondition(input["format"] as? String == "mp3")
        precondition(input["sample_rate"] as? Int == 24000 && input["rate"] as? Double == 1)
        for (address, token, timeout) in [
            ("http://example.invalid/tts", "test", 60.0),
            ("https://user:secret@example.invalid/tts", "test", 60.0),
            ("https://example.invalid/tts?secret=test", "test", 60.0),
            (endpoint.absoluteString, "test\r\nX-Injected: yes", 60.0),
            (endpoint.absoluteString, " ", 60.0),
            (endpoint.absoluteString, "test", Double.nan)
        ] {
            do {
                _ = try QwenTTSRequest.make(endpoint: URL(string: address)!, text: "测试", voice: "test",
                                            token: token, timeout: timeout)
                preconditionFailure("非法请求必须被拒绝")
            } catch is URLError { }
        }
        print("网关请求离线检查通过：POST、鉴权、两层 JSON 及地址／注入边界；未联网")
    }
}
