import Foundation

/// 原包会话指向 Claude 的对话记录，不能与手动保存的终端书签混为一谈。
struct ClaudeSessionRecord: Identifiable, Equatable, Sendable {
    let id: String
    let file: URL
    let workingDirectory: String
    let lastActivity: Date
    let lastPrompt: String
    enum NameSource: String, Sendable { case custom, ai, none }
    var name: String?
    var nameSource: NameSource = .none
    var hasInlineCustomTitle = false
    var runningPID: Int32?
    var runningStateUnknown = false

    var displayName: String { name ?? "（这个会话没起过名字）" }
    var isRunning: Bool { runningPID != nil }
    var preview: String {
        // 原包本地命令输出不展示为问题预览；其他清洗规则仍需对照。
        lastPrompt.contains("<local-command-") ? "" : lastPrompt
    }
    var isValidResumeID: Bool {
        // 引号只阻止 shell 注入，不能阻止客户端把以减号开头的编号当选项。
        guard let first = id.utf8.first,
              (48...57).contains(first) || (65...90).contains(first) || (97...122).contains(first) else { return false }
        return id.utf8.count <= 128 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
    var resumeCommand: String {
        "claude --resume '" + id.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

enum ClaudeSessionScanner {
    enum TitleError: LocalizedError {
        case empty, tooLong
        var errorDescription: String? {
            switch self {
            case .empty: return "会话名称不能为空"
            case .tooLong: return "会话名称不能超过 120 个字符"
            }
        }
    }

    /// 原包先去除首尾空白，再按 Swift 字符数检查；不按 UTF-8 字节截断中文。
    static func validatedTitle(_ input: String) throws -> String {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TitleError.empty }
        guard title.count <= 120 else { throw TitleError.tooLong }
        return title
    }

    /// 只读扫描顶层会话，不进入子代理和记忆目录，也不修改原始文件。
    static func scan(root: URL) throws -> [ClaudeSessionRecord] {
        try Task.checkCancellation()
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return [] }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let projects = try manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var records: [ClaudeSessionRecord] = []
        for project in projects {
            try Task.checkCancellation()
            let projectValues = try project.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let canonicalProject = project.resolvingSymlinksInPath().standardizedFileURL
            guard projectValues.isDirectory == true, projectValues.isSymbolicLink != true,
                  canonicalProject.path.hasPrefix(canonicalRoot.path + "/") else { continue }
            let files = try manager.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            for file in files where file.pathExtension == "jsonl" {
                try Task.checkCancellation()
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                let canonicalFile = file.resolvingSymlinksInPath().standardizedFileURL
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      canonicalFile.path.hasPrefix(canonicalProject.path + "/") else { continue }
                if let record = try read(file: file) { records.append(record) }
            }
        }
        let unique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: {
            $0.lastActivity >= $1.lastActivity ? $0 : $1
        })
        return unique.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    static func read(file: URL) throws -> ClaudeSessionRecord? {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var pending = Data()
        var sessionID: String?
        var directory: String?
        var lastPrompt = ""
        var customTitle: String?
        var aiTitle: String?
        var lastActivity = Date.distantPast
        let filenameID = file.deletingPathExtension().lastPathComponent
        let expectedID = UUID(uuidString: filenameID) != nil ? filenameID.lowercased() : nil
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        func consume(_ line: Data) {
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  value["isSidechain"] as? Bool != true else { return }
            if let id = value["sessionId"] as? String, let expectedID, id.lowercased() != expectedID {
                return
            }
            if let title = value["customTitle"] as? String, !title.isEmpty { customTitle = title }
            if let title = value["aiTitle"] as? String, !title.isEmpty { aiTitle = title }
            if let id = value["sessionId"] as? String, !id.isEmpty { sessionID = id }
            if let cwd = value["cwd"] as? String, cwd.hasPrefix("/") { directory = cwd }
            if let timestamp = value["timestamp"] as? String,
               let date = formatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp) {
                lastActivity = max(lastActivity, date)
            }
            if value["type"] as? String == "last-prompt", let prompt = value["lastPrompt"] as? String {
                lastPrompt = prompt
            } else if value["type"] as? String == "user", value["isMeta"] as? Bool != true,
                      let message = value["message"] as? [String: Any] {
                if let content = message["content"] as? String {
                    lastPrompt = content
                } else if let blocks = message["content"] as? [[String: Any]] {
                    let text = blocks.filter { $0["type"] as? String == "text" }
                        .compactMap { $0["text"] as? String }.joined(separator: "\n")
                    if !text.isEmpty { lastPrompt = text }
                }
            }
        }
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                try Task.checkCancellation()
                consume(Data(pending[..<newline]))
                pending.removeSubrange(...newline)
            }
            // 对异常超长行明确报错，避免隐藏数据损坏或无限增长。
            if pending.count > 32 * 1024 * 1024 {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        if !pending.isEmpty { consume(pending) }
        guard let sourceID = sessionID ?? expectedID, let cwd = directory else { return nil }
        let id = UUID(uuidString: sourceID)?.uuidString.lowercased() ?? sourceID
        var record = ClaudeSessionRecord(id: id, file: file, workingDirectory: cwd,
                                         lastActivity: lastActivity, lastPrompt: lastPrompt)
        let sidecarTitle = customTitle == nil ? readSidecarTitle(for: file) : nil
        record.name = customTitle ?? sidecarTitle ?? aiTitle
        record.hasInlineCustomTitle = customTitle != nil
        record.nameSource = customTitle != nil || sidecarTitle != nil ? .custom : (aiTitle != nil ? .ai : .none)
        return record
    }

    private static func readSidecarTitle(for file: URL) -> String? {
        let id = file.deletingPathExtension().lastPathComponent
        guard UUID(uuidString: id) != nil else { return nil }
        let project = file.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let sidecar = project.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("custom-title.json").resolvingSymlinksInPath().standardizedFileURL
        // 不允许名称文件的软链接逃出当前项目目录，也避免异常大文件占满内存。
        guard sidecar.path.hasPrefix(project.path + "/"),
              let size = try? sidecar.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 1024 * 1024,
              let data = try? Data(contentsOf: sidecar),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = value["customTitle"] as? String, !title.isEmpty else { return nil }
        return title
    }
}
