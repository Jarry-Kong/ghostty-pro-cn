import Foundation

/// 按原包证据构造请求；本类型不发起网络连接或读取凭据。
enum QwenTTSRequest {
    static let defaultModel = "qwen-audio-3.0-tts-plus"

    static func endpoint(baseURL: String) throws -> URL {
        guard let endpoint = URL(string: try normalizedBaseURL(baseURL) + "/bailian/audio/tts") else { throw URLError(.badURL) }
        return endpoint
    }

    static func normalizedBaseURL(_ baseURL: String) throws -> String {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard base.rangeOfCharacter(from: .controlCharacters) == nil,
              let url = URL(string: base), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw URLError(.badURL) }
        return base
    }

    static func timeout(characterCount: Int) -> TimeInterval {
        min(180, 30 + Double(max(0, characterCount)) * 8 / 100)
    }

    static func make(endpoint: URL, text: String, voice: String, model: String = defaultModel,
                     token: String, timeout: TimeInterval? = nil) throws -> URLRequest {
        let timeout = timeout ?? Self.timeout(characterCount: text.trimmingCharacters(in: .whitespacesAndNewlines).count)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw URLError(.badURL) }
        var request = try authorizedRequest(endpoint: endpoint, token: token, timeout: timeout)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": ["text": text, "voice": voice, "format": "mp3", "sample_rate": 24000, "rate": 1.0]
        ])
        return request
    }

    static func authorizedRequest(endpoint: URL, token: String, timeout: TimeInterval) throws -> URLRequest {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host?.isEmpty == false,
              endpoint.user == nil, endpoint.password == nil, endpoint.fragment == nil,
              endpoint.query == nil, timeout.isFinite, timeout > 0,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              token.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }
}
