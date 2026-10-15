import Foundation

@main
enum SpeechCleanerCheck {
    static func main() throws {
        let source = "# **标题**\n- [x] 完成\n- [ ] 待做\n```swift\nlet value = [1, 2];\n```\n[结束](https://example.com)"
        let skip = SpeechTextCleaner(codeMode: .skip).cleanIntoSegments(source).joined(separator: "\n")
        let simple = SpeechTextCleaner(codeMode: .simplify).cleanIntoSegments(source).joined(separator: "\n")
        let literal = SpeechTextCleaner(codeMode: .verbatim).cleanIntoSegments(source).joined(separator: "\n")
        precondition(skip.contains("已完成：完成") && skip.contains("还没做：待做"))
        precondition(!skip.contains("let value") && skip.contains("1 行，请看屏幕"))
        precondition(simple.contains("let value = 1 2") && !simple.contains("[1, 2];"))
        precondition(literal.contains("let value = [1, 2];"))
        precondition([skip, simple, literal].allSatisfy { $0.hasPrefix("标题") && $0.hasSuffix("结束") })
        let legacy = try JSONDecoder().decode(VoiceSettings.CodeMode.self, from: Data("\"read\"".utf8))
        precondition(legacy == .verbatim)
        for mode in VoiceSettings.CodeMode.allCases {
            let decoded = try JSONDecoder().decode(VoiceSettings.CodeMode.self, from: JSONEncoder().encode(mode))
            precondition(decoded == mode)
        }
        let cleaner = SpeechTextCleaner(codeMode: .skip)
        let path = cleaner.stripInline("查看 /Users/example/project/Sources/main.swift:123，保留 42。")
        precondition(path.contains("main.swift 第 123 行") && path.contains("42"))
        let decorated = cleaner.stripInline("✅ 完成 → 下一步 • 重点 · 说明 🧪")
        precondition(decorated.contains("完成") && decorated.contains("下一步") && decorated.contains("重点") && decorated.contains("说明"))
        precondition(!decorated.contains("✅") && !decorated.contains("→") && !decorated.contains("•") && !decorated.contains("·") && !decorated.contains("🧪"))
        let table = cleaner.renderLines("| 项目 | 数量 |\n| --- | --- |\n| **文件** | 42 |\n结束")
        precondition(table.contains("下面是一个表格，各列分别是：项目，数量。"))
        precondition(table.contains("项目：文件，数量：42。") && table.last == "结束")
        let borderlessTable = cleaner.renderLines("项目 | 数量\n--- | ---\n文件 | 42")
        precondition(borderlessTable == ["下面是一个表格，各列分别是：项目，数量。", "项目：文件，数量：42。"])
        let shortDividerTable = cleaner.renderLines("项目 | 数量\n-- | :-\n文件 | 42")
        precondition(shortDividerTable == borderlessTable)
        precondition(cleaner.renderLines("开始\n-_*\n结束") == ["开始", "结束"])
        precondition(cleaner.cleanIntoSegments("2. 第二项") == ["第二，第二项"])
        precondition(SpeechTextCleaner.simplifyPath("HTTP:200") == "HTTP:200")
        precondition(SpeechTextCleaner.splitIntoSentences("他说：“金额 3.14。”下一句！") == ["他说：“金额 3.14。”", "下一句！"])
        precondition(SpeechTextCleaner.splitIntoSentences("Dr. Smith has 3.14 dollars. Next sentence.") ==
            ["Dr. Smith has 3.14 dollars.", "Next sentence."])
        precondition(SpeechTextCleaner.splitIntoSentences("See Fig. 2 and approx. 3 pages. Done.") ==
            ["See Fig. 2 and approx. 3 pages.", "Done."])
        precondition(SpeechTextCleaner.splitIntoSentences("A Ph.D. student arrived. Next.") ==
            ["A Ph.D. student arrived.", "Next."])
        let unpunctuated = String(repeating: "长", count: 200)
        precondition(SpeechTextCleaner.splitIntoSentences(unpunctuated) == [unpunctuated])
        precondition(SpeechTextCleaner.mergeShortPieces([String(repeating: "长", count: 105), String(repeating: "短", count: 14)]).count == 1)
        precondition(SpeechTextCleaner.mergeShortPieces([String(repeating: "长", count: 106), String(repeating: "短", count: 14)]).count == 2)
        print("清洗检查通过：三种模式实际输出、标题／链接／待办、代码外正文保留、旧设置兼容及三模式序列化")
    }
}
