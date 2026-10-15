import Foundation

enum ScriptRewriteRequest {
    static func endpoint(baseURL: String) throws -> URL {
        var base = try QwenTTSRequest.normalizedBaseURL(baseURL)
        if base.hasSuffix("/v1/messages") { return URL(string: base)! }
        if base.hasSuffix("/v1") { base = try QwenTTSRequest.normalizedBaseURL(String(base.dropLast(3))) }
        guard let url = URL(string: base + "/v1/messages") else { throw URLError(.badURL) }
        return url
    }

    enum Strength: String, Codable, CaseIterable, Identifiable {
        case conservative, natural
        var id: String { rawValue }
    }

    static func systemPrompt(strength: Strength) -> String {
        let intro = """
        你要把一段技术性的中文回复改写成"念给人听"的口播稿。这段文字会被语音合成朗读。

        最重要的一条：不要增加、删除或改动任何事实、数字、文件名、结论。读者是靠听来了解这些内容的，改错一个数字或漏掉一个结论，比稿子念起来生硬严重得多。吃不准的地方，宁可照抄原文的说法。
        """ + "\n\n"
        let instruction = strength == .conservative
            ? "改写力度：保守。措辞尽量照原文，主要工作是去掉符号、拆开长句、把表格和列表讲成顺口的话。不要替换原文的用词，也不要调整段落顺序。"
            : "改写力度：自然。可以重组句子结构、调整语序，让它像一个人在口头讲述。但事实、数字、结论、专有名词必须与原文完全一致。"
        let rules = """
        具体的转换规则：
        1. 去掉所有 Markdown 符号：星号、井号、竖线、反引号、方括号、多余的横线。
        2. 表格改写成顺畅的叙述。可以先说这个表格在讲什么，再逐行说清楚。不要念"竖线"，也不要保留表格的框线。
        3. 代码块不要念出内容，用一句话交代即可，例如"这里有一段 Swift 代码，大约十行，请看屏幕"。但代码块之外的说明文字要保留。
        4. 长文件路径只保留文件名。形如"某路径:123"的写法改成"某文件第 123 行"。
        5. 列表改成口语序号："第一"、"第二"、"第三"。原文已有编号的沿用原编号。
        6. 待办清单要念出状态，例如"已完成：某事"、"还没做：某事"。
        7. 长句拆短，一句话控制在四十个字以内，听起来才不费劲。
        8. 去掉 emoji 和纯装饰性符号。箭头按意思念，例如流程箭头念成"然后"。

        输出要求：
        - 只输出改写后的正文，不要任何前言、后记、解释或说明。
        - 不要写"以下是改写后的内容"这类过渡语，那句话会被一起念出来。
        - 不要用 Markdown 格式包裹输出。
        - 保持原文的语言（中文原文就输出中文）。
        """
        return intro + instruction + "\n\n" + rules
    }

    static func make(endpoint: URL, token: String, model: String, text: String, strength: Strength) throws -> URLRequest {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw URLError(.badURL) }
        var request = try QwenTTSRequest.authorizedRequest(endpoint: endpoint, token: token, timeout: 20)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "max_tokens": 8000, "system": systemPrompt(strength: strength),
            "messages": [["role": "user", "content": "请把下面这段回复改写成口播稿：\n\n" + text]]
        ])
        return request
    }
}
