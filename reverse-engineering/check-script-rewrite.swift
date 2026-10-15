import Foundation
import CryptoKit

@main
enum CheckScriptRewrite {
    static func main() throws {
        for base in ["https://example.invalid", "https://example.invalid/v1", "https://example.invalid/v1/messages",
                     " https://example.invalid/v1/// "] {
            let endpoint = try ScriptRewriteRequest.endpoint(baseURL: base)
            precondition(endpoint.absoluteString == "https://example.invalid/v1/messages")
        }
        let prefix = try ScriptRewriteRequest.endpoint(baseURL: "https://example.invalid/team/v1/")
        precondition(prefix.path == "/team/v1/messages")
        for base in ["", "http://example.invalid/v1", "https://example.invalid?token=secret"] {
            do { _ = try ScriptRewriteRequest.endpoint(baseURL: base); preconditionFailure("非法改写地址必须拒绝") }
            catch is URLError { }
        }
        let hashes: [ScriptRewriteRequest.Strength: String] = [
            .conservative: "020b961237d25dcb96d71cf106c583dcea13bcd0170257d78e829bcda71735f1",
            .natural: "41f9cf28d8ba414303bfb032aa46093a70c977754da8cc58f22456f219431041"
        ]
        for strength in ScriptRewriteRequest.Strength.allCases {
            let prompt = ScriptRewriteRequest.systemPrompt(strength: strength)
            let hash = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
            precondition(hash == hashes[strength], "系统提示词必须与原包字节一致")
        }
        let request = try ScriptRewriteRequest.make(endpoint: URL(string: "https://example.invalid/v1/messages")!,
                                                     token: "synthetic", model: "test-model", text: "测试文字 123", strength: .conservative)
        precondition(request.httpMethod == "POST" && request.timeoutInterval == 20)
        precondition(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(Set(body.keys) == Set(["model", "max_tokens", "system", "messages"]))
        precondition(body["max_tokens"] as? Int == 8000 && body["model"] as? String == "test-model")
        let messages = body["messages"] as! [[String: String]]
        precondition(messages == [["role": "user", "content": "请把下面这段回复改写成口播稿：\n\n测试文字 123"]])
        let response = try JSONSerialization.data(withJSONObject: ["content": [
            ["type": "text", "text": "  第一段"], ["type": "thinking", "thinking": "不得朗读"],
            ["type": "tool_use", "text": "不得朗读工具"], ["type": "text", "text": "第二段 \n"]
        ]])
        precondition(ScriptRewriteResponse.text(from: response, statusCode: 200) == "第一段\n第二段")
        precondition(ScriptRewriteResponse.text(from: response, statusCode: 500) == nil)
        for object: [String: Any] in [["content": "不是文本块数组"], ["content": [["type": "text", "text": " \n"]]],
                                     ["content": [["type": "thinking", "text": "不得朗读"]]]] {
            let data = try JSONSerialization.data(withJSONObject: object)
            precondition(ScriptRewriteResponse.text(from: data, statusCode: 200) == nil)
        }
        precondition(ScriptRewriteResponse.text(from: Data("坏 JSON".utf8), statusCode: 200) == nil)
        print("改写请求离线检查通过：原包提示词双哈希、请求头、20 秒超时及四项请求体；未联网")
    }
}
