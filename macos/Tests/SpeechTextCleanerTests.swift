import XCTest
@testable import Ghostty

final class SpeechTextCleanerTests: XCTestCase {
    func testSentenceClosersDecimalsAndMergeBoundaries() {
        XCTAssertEqual(SpeechTextCleaner.splitIntoSentences("他说：“金额 3.14。”下一句！"),
                       ["他说：“金额 3.14。”", "下一句！"])
        XCTAssertEqual(SpeechTextCleaner.splitIntoSentences("Dr. Smith has 3.14 dollars. Next sentence."),
                       ["Dr. Smith has 3.14 dollars.", "Next sentence."])
        XCTAssertEqual(SpeechTextCleaner.mergeShortPieces([String(repeating: "长", count: 105), String(repeating: "短", count: 14)]).count, 1)
        XCTAssertEqual(SpeechTextCleaner.mergeShortPieces([String(repeating: "长", count: 106), String(repeating: "短", count: 14)]).count, 2)
        XCTAssertEqual(SpeechTextCleaner.mergeShortPieces(["前句", String(repeating: "长", count: 15)]).count, 2)
    }
    func testPathsLineNumbersTablesAndOrderedLists() {
        let cleaner = SpeechTextCleaner(codeMode: .skip)
        XCTAssertTrue(cleaner.stripInline("看 /Users/example/project/main.swift:123，数量 42").contains("main.swift 第 123 行"))
        XCTAssertEqual(SpeechTextCleaner.simplifyPath("HTTP:200"), "HTTP:200")
        XCTAssertEqual(SpeechTextCleaner.simplifyPath("main.swift:12:3"), "main.swift 第 12 行")
        XCTAssertEqual(cleaner.cleanIntoSegments("2. 事项"), ["第二，事项"])
        XCTAssertEqual(cleaner.cleanIntoSegments("21. 事项"), ["第21，事项"])
        XCTAssertEqual(cleaner.renderLines("| 名称 | 值 |\n| :--- | ---: |\n| 文件 | 42 |"),
                       ["下面是一个表格，各列分别是：名称，值。", "名称：文件，值：42。"])
    }
    func testCodeModesHaveDifferentEffectiveOutput() {
        let source = "说明\n```swift\nlet value = [1, 2];\n```\n结束"
        let skipped = SpeechTextCleaner(codeMode: .skip).cleanIntoSegments(source).joined(separator: "\n")
        let simplified = SpeechTextCleaner(codeMode: .simplify).cleanIntoSegments(source).joined(separator: "\n")
        let literal = SpeechTextCleaner(codeMode: .verbatim).cleanIntoSegments(source).joined(separator: "\n")
        XCTAssertFalse(skipped.contains("let value"))
        XCTAssertTrue(skipped.contains("1 行，请看屏幕"))
        XCTAssertTrue(simplified.contains("let value = 1 2"))
        XCTAssertFalse(simplified.contains("[1, 2];"))
        XCTAssertTrue(literal.contains("let value = [1, 2];"))
        XCTAssertTrue([skipped, simplified, literal].allSatisfy { $0.hasSuffix("结束") })
    }

    func testMarkdownAndTodoTextArePreservedWithoutMarkers() {
        let cleaner = SpeechTextCleaner(codeMode: .skip)
        XCTAssertEqual(cleaner.renderLines("# **标题**\n- [x] 完成\n- [ ] 待做\n[说明](https://example.com)"),
                       ["标题", "已完成：完成", "还没做：待做", "说明"])
        XCTAssertEqual(cleaner.stripInline("![图片](https://example.com/a.png) `文件名`"), " 文件名")
        XCTAssertTrue(cleaner.cleanIntoSegments(" \n\t").isEmpty)
    }

    func testLegacyReadSettingIsNotDiscarded() throws {
        XCTAssertEqual(try JSONDecoder().decode(VoiceSettings.CodeMode.self, from: Data("\"read\"".utf8)), .verbatim)
        XCTAssertEqual(VoiceSettings().codeMode, .skip)
        for mode in VoiceSettings.CodeMode.allCases {
            XCTAssertEqual(try JSONDecoder().decode(VoiceSettings.CodeMode.self, from: JSONEncoder().encode(mode)), mode)
        }
    }
}
