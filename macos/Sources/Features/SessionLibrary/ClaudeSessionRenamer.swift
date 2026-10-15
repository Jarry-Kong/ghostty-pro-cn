import Foundation

/// 按原包只修改名称侧文件，不重写对话正文。
enum ClaudeSessionRenamer {
    enum RenameError: LocalizedError {
        case unsafePath, invalidFile, changed
        var errorDescription: String? {
            switch self {
            case .unsafePath: return "名称路径不安全，未修改会话"
            case .invalidFile: return "原名称文件损坏或格式不支持，未覆盖原数据"
            case .changed: return "会话记录已变化，请刷新后再改名"
            }
        }
    }

    @discardableResult
    static func rename(_ record: ClaudeSessionRecord, to input: String, root: URL) throws -> ClaudeSessionRecord {
        let title = try ClaudeSessionScanner.validatedTitle(input)
        let manager = FileManager.default
        let allowedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = record.file.standardizedFileURL
        let project = file.deletingLastPathComponent()
        guard UUID(uuidString: record.id) != nil,
              file.lastPathComponent.lowercased() == record.id.lowercased() + ".jsonl",
              project.deletingLastPathComponent() == allowedRoot,
              file.resolvingSymlinksInPath() == file,
              try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw RenameError.unsafePath
        }
        guard let current = try ClaudeSessionScanner.read(file: file),
              current.id == record.id, current.name == record.name,
              current.lastActivity == record.lastActivity else { throw RenameError.changed }
        let directory = project.appendingPathComponent(file.deletingPathExtension().lastPathComponent)
        let sidecar = directory.appendingPathComponent("custom-title.json")
        guard directory.resolvingSymlinksInPath() == directory,
              sidecar.resolvingSymlinksInPath() == sidecar else { throw RenameError.unsafePath }
        var previous: Data?
        var value: [String: Any] = [:]
        if manager.fileExists(atPath: sidecar.path) {
            let properties = try sidecar.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard properties.isRegularFile == true, let size = properties.fileSize, size <= 1024 * 1024 else {
                throw RenameError.invalidFile
            }
            let data = try Data(contentsOf: sidecar)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RenameError.invalidFile
            }
            previous = data
            value = object
        }
        value["customTitle"] = title
        let replacement = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        if manager.fileExists(atPath: directory.path) {
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw RenameError.unsafePath
            }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
        }
        if let previous {
            let backup = directory.appendingPathComponent(".custom-title.backup-" + UUID().uuidString + ".json")
            try previous.write(to: backup, options: [.withoutOverwriting])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        // 再次检查侧文件，避免覆盖检测期间的客户端更新。
        let latest = manager.fileExists(atPath: sidecar.path) ? try Data(contentsOf: sidecar) : nil
        guard latest == previous else { throw RenameError.changed }
        try replacement.write(to: sidecar, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sidecar.path)
        guard let written = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any],
              written["customTitle"] as? String == title else {
            // 不覆盖并发写入者；只回滚仍然等于本次写入内容的侧文件。
            if try Data(contentsOf: sidecar) == replacement {
                if let previous { try previous.write(to: sidecar, options: [.atomic]) }
                else { try manager.removeItem(at: sidecar) }
            }
            throw RenameError.changed
        }
        // 原包成功后直接更新返回记录；正文内旧名称仍不改写。
        var updated = current
        updated.name = title
        updated.nameSource = .custom
        return updated
    }
}
