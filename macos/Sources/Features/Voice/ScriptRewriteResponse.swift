import Foundation

enum ScriptRewriteResponse {
    /// 无可用改写时返回 nil，调用者保留规则清洗稿；不朗读思考或工具内容。
    static func text(from data: Data, statusCode: Int) -> String? {
        guard statusCode == 200, data.count <= 4 * 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else { return nil }
        let text = content.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
