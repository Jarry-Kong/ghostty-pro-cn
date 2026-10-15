import Foundation

/// 独立目的地址／令牌由调用者明确提供；用户发送许可在控制器中取得。
enum ScriptRewriter {
    static func shouldRewrite(_ text: String, enabled: Bool, minimumLength: Int, comparison: Bool? = nil) -> Bool {
        comparison ?? (enabled && isWorthRewriting(text, minimumLength: minimumLength))
    }

    static func isWorthRewriting(_ text: String, minimumLength: Int = 120) -> Bool {
        let count = text.count
        return count >= (minimumLength > 0 ? minimumLength : 120) && count <= 8000
    }

    static func rewrite(baseURL: String, token: String, model: String, text: String,
                        strength: ScriptRewriteRequest.Strength,
                        configuration: URLSessionConfiguration = .ephemeral) async throws -> String? {
        try Task.checkCancellation()
        let endpoint = try ScriptRewriteRequest.endpoint(baseURL: baseURL)
        let request = try ScriptRewriteRequest.make(endpoint: endpoint, token: token, model: model, text: text, strength: strength)
        let response = try await QwenTTSClient(configuration: configuration).fetch(request, maximumBytes: 4 * 1024 * 1024)
        try Task.checkCancellation()
        return ScriptRewriteResponse.text(from: response.data, statusCode: response.status)
    }
}
