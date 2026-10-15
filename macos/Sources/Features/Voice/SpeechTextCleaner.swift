import Foundation

/// 基于原包已取证规则构建口播稿；完整表格与句段边界仍需对照。
struct SpeechTextCleaner {
    let codeMode: VoiceSettings.CodeMode

    func cleanIntoSegments(_ input: String) -> [String] {
        Self.mergeShortPieces(renderLines(input).flatMap(Self.splitIntoSentences))
    }

    func renderLines(_ input: String) -> [String] {
        var pieces: [String] = []
        var code: [String] = []
        var fence: String?
        var language = ""
        var table: [[String]] = []
        var tableHasHeader = false
        func flushTable() {
            guard !table.isEmpty else { return }
            if tableHasHeader {
                let headers = table.removeFirst()
                pieces.append("下面是一个表格，各列分别是：" + headers.joined(separator: "，") + "。")
                for row in table {
                    pieces.append(row.enumerated().map { index, cell in
                        index < headers.count && !headers[index].isEmpty ? headers[index] + "：" + cell : cell
                    }.joined(separator: "，") + "。")
                }
            } else {
                pieces.append("下面是一个表格。")
                pieces.append(contentsOf: table.map { $0.joined(separator: "，") + "。" })
            }
            table.removeAll()
            tableHasHeader = false
        }
        func flushCode() {
            let nonempty = code.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !nonempty.isEmpty else { code.removeAll(); return }
            let label = Self.languageName(language)
            switch codeMode {
            case .skip:
                pieces.append("（这里有一段\(label)，共 \(nonempty.count) 行，请看屏幕）")
            case .simplify:
                let simplified = Self.replace(nonempty.joined(separator: "\n"), pattern: #"[{}\[\]();,]"#, with: " ")
                pieces.append("（下面念一段\(label)）")
                pieces.append(Self.replace(simplified, pattern: #"\s{2,}"#, with: " "))
            case .verbatim:
                pieces.append(nonempty.joined(separator: "\n"))
            }
            code.removeAll()
        }
        for line in input.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let marker = fence {
                if trimmed.hasPrefix(marker) { flushCode(); fence = nil }
                else { code.append(line) }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushTable()
                fence = String(trimmed.prefix(3))
                language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if Self.isTableRow(trimmed) {
                let cells = Self.splitTableRow(trimmed)
                    .map { stripInline($0) }
                if Self.isTableDivider(trimmed) {
                    tableHasHeader = table.count == 1
                } else { table.append(cells) }
                continue
            }
            flushTable()
            if Self.isHorizontalRule(trimmed) {
                continue
            } else if let match = Self.match(trimmed, pattern: #"^[-*+]\s+\[([ xX])\]\s+(.*)$"#) {
                pieces.append((match[1].lowercased() == "x" ? "已完成：" : "还没做：") + stripInline(match[2]))
            } else if let match = Self.match(trimmed, pattern: #"^(\d{1,3})[.)]\s+(.*)$"#), let number = Int(match[1]) {
                pieces.append(Self.chineseOrdinal(number) + "，" + stripInline(match[2]))
            } else {
                let heading = Self.replace(trimmed, pattern: #"^(#{1,6})\s+(.*)$"#, with: "$2")
                let bullet = Self.replace(heading, pattern: #"^[-*+]\s+"#, with: "")
                pieces.append(stripInline(bullet))
            }
        }
        flushTable()
        if fence != nil { flushCode() }
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func splitIntoSentences(_ input: String) -> [String] {
        let characters = Array(input)
        let closers: Set<Character> = ["”", "’", "\"", "'", ")", "）", "]", "】", "」", "』", "》"]
        var pieces: [String] = []
        var buffer = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            buffer.append(character)
            let endsSentence = "。！？!?…".contains(character) ||
                (character == "." && isEnglishSentencePeriod(characters, at: index))
            index += 1
            if endsSentence {
                while index < characters.count && (closers.contains(characters[index]) || characters[index] == "…") {
                    buffer.append(characters[index])
                    index += 1
                }
                let piece = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { pieces.append(piece) }
                buffer = ""
            }
        }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    static func mergeShortPieces(_ pieces: [String]) -> [String] {
        var result: [String] = []
        for piece in pieces where !piece.isEmpty {
            if piece.count <= 14, let previous = result.last, previous.count + piece.count + 1 <= 120 {
                result[result.count - 1] = previous + "\n" + piece
            } else { result.append(piece) }
        }
        return result
    }

    private static func isEnglishSentencePeriod(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return false }
        if index + 1 < characters.count && !characters[index + 1].isWhitespace &&
            !"\"'”’)]）】」』》".contains(characters[index + 1]) { return false }
        var start = index
        while start > 0 && !characters[start - 1].isWhitespace { start -= 1 }
        let word = String(characters[start..<index]).lowercased()
        // 原包静态集合的 28 项，句点前命中时不拆句。
        let abbreviations: Set<String> = [
            "e.g", "i.e", "etc", "vs", "cf", "al", "approx", "ca",
            "mr", "mrs", "ms", "dr", "prof", "st", "jr", "sr",
            "fig", "no", "inc", "ltd", "co", "vol", "pp", "a.m",
            "p.m", "u.s", "u.k", "ph.d",
        ]
        if abbreviations.contains(word) || (word.count == 1 && word.first?.isLetter == true) { return false }
        return true
    }

    func stripInline(_ input: String) -> String {
        var text = Self.replace(input, pattern: #"!\[[^\]]*\]\([^)]*\)"#, with: "")
        text = Self.replace(text, pattern: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1")
        text = Self.replace(text, pattern: #"\*\*\*([^*]+)\*\*\*"#, with: "$1")
        text = Self.replace(text, pattern: #"\*\*([^*]+)\*\*"#, with: "$1")
        text = Self.replace(text, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, with: "$1")
        text = Self.replace(text, pattern: #"`([^`]+)`"#, with: "$1")
        text = Self.replaceMatches(text, pattern: #"(?<![\w`/])((?:/[\w.\-]+){2,}(?::\d+)?)"#) {
            Self.simplifyPath($0)
        }
        text = Self.removeDecorations(text)
        text = Self.replace(text, pattern: #"([，。、：；！？])\s+"#, with: "$1")
        return text
    }

    private static func removeDecorations(_ input: String) -> String {
        String(input.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !(
                (0x1F000...0x1FAFF).contains(value) ||
                (0x2190...0x21FF).contains(value) ||
                (0x2300...0x27BF).contains(value) ||
                (0x2B00...0x2BFF).contains(value) ||
                (0x2500...0x257F).contains(value) ||
                (0x2580...0x259F).contains(value) ||
                value == 0xFE0F || value == 0x200D ||
                value == 0x2022 || value == 0x00B7)
        })
    }

    private static func isTableRow(_ input: String) -> Bool {
        input.contains("|") && input.filter { $0 != "|" }.count > 1
    }

    private static func splitTableRow(_ input: String) -> [String] {
        var row = input
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func isTableDivider(_ input: String) -> Bool {
        input.replacingOccurrences(of: " ", with: "").allSatisfy {
            $0 == "|" || $0 == "-" || $0 == ":"
        }
    }

    private static func isHorizontalRule(_ input: String) -> Bool {
        input.count >= 3 && input.allSatisfy {
            $0 == "-" || $0 == "*" || $0 == "_"
        }
    }

    static func simplifyPath(_ input: String) -> String {
        let line = match(input, pattern: #"^(.+?):(\d+)(?::\d+)?$"#)
        let path = line?[1] ?? input
        guard path.contains("/") || path.contains(".") else { return input }
        let shortened = path.contains("/") && path.count >= 13 ? (path as NSString).lastPathComponent : path
        return line.map { shortened + " 第 " + $0[2] + " 行" } ?? shortened
    }

    static func chineseOrdinal(_ number: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard (1...20).contains(number) else { return "第\(number)" }
        if number < 10 { return "第" + digits[number] }
        let tens = number / 10
        let ones = number % 10
        return "第" + (tens == 1 ? "" : digits[tens]) + "十" + (ones == 0 ? "" : digits[ones])
    }

    private static func replaceMatches(_ text: String, pattern: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let sourceRange = Range(match.range, in: text), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(text[sourceRange])))
        }
        return result
    }

    private static func languageName(_ language: String) -> String {
        switch language.lowercased() {
        case "ts", "typescript": return "TypeScript 代码"
        case "js", "javascript": return "JavaScript 代码"
        case "swift": return "Swift 代码"
        case "": return "代码"
        default: return language + " 代码"
        }
    }

    private static func replace(_ text: String, pattern: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private static func match(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map {
            Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
