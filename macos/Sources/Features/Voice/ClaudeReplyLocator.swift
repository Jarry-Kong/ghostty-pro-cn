import Foundation

/// 按原包的目录、名称精确匹配、包含匹配及最近记录回退定位。
enum ClaudeReplyLocator {
    static func normalizedTitle(_ input: String?) -> String? {
        guard let input else { return nil }
        let scalars = input.unicodeScalars.filter {
            let value = $0.value
            return !(0x1F000..<0x1FB00).contains(value) && !(0x2190..<0x2200).contains(value)
                && !(0x2300..<0x27C0).contains(value) && !(0x2B00..<0x2C00).contains(value)
                && ![0xFE0F, 0x200D, 0x2731, 0x2734].contains(value)
        }
        let title = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func select(records: [ClaudeSessionRecord], cwd: String, terminalTitle: String?) -> ClaudeSessionRecord? {
        let directory = URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath().path
        let candidates = records.filter {
            URL(fileURLWithPath: $0.workingDirectory).standardizedFileURL.resolvingSymlinksInPath().path == directory
        }
        guard candidates.count > 1 else { return candidates.first }
        if let title = normalizedTitle(terminalTitle) {
            if let exact = candidates.first(where: { normalizedTitle($0.name) == title }) { return exact }
            if title.count >= 4, let partial = candidates.first(where: {
                guard let name = normalizedTitle($0.name), name.count >= 4 else { return false }
                return title.contains(name) || name.contains(title)
            }) { return partial }
        }
        // 原包无标题匹配时回退最近候选；候选顺序由调用者按文件修改时间提供。
        return candidates.first
    }

    static func find(root: URL, cwd: String, terminalTitle: String?) throws -> ClaudeSessionRecord? {
        try Task.checkCancellation()
        guard cwd.hasPrefix("/") else { return nil }
        let records = try ClaudeSessionScanner.scan(root: root)
        let matching = records.filter {
            URL(fileURLWithPath: $0.workingDirectory).standardizedFileURL.resolvingSymlinksInPath()
                == URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath()
        }
        let sorted = try matching.map { record in
            try Task.checkCancellation()
            return (record, try record.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }.map(\.0)
        return select(records: Array(sorted.prefix(12)), cwd: cwd, terminalTitle: terminalTitle)
    }
}
