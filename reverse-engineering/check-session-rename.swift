import Foundation

@main
enum SessionRenameCheck {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("ghostty-rename-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let file = project.appendingPathComponent(id + ".jsonl")
        let source = Data("{\"sessionId\":\"\(id)\",\"cwd\":\"/tmp\",\"aiTitle\":\"旧名称\"}\n".utf8)
        try source.write(to: file)
        var record = try require(ClaudeSessionScanner.read(file: file))
        record = try ClaudeSessionRenamer.rename(record, to: " 新中文名称 ", root: root)
        precondition(record.name == "新中文名称")
        precondition(tryData(file) == source)
        record = try ClaudeSessionRenamer.rename(record, to: "第二个名称", root: root)
        precondition(record.name == "第二个名称")
        let directory = project.appendingPathComponent(id)
        let backups = try manager.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".custom-title.backup-") }
        precondition(backups.count == 1)
        do {
            _ = try ClaudeSessionRenamer.rename(record, to: "越界", root: project)
            preconditionFailure("未拒绝错误根目录")
        } catch is ClaudeSessionRenamer.RenameError { }
        let sidecar = directory.appendingPathComponent("custom-title.json")
        try Data("损坏数据".utf8).write(to: sidecar)
        let corruptRecord = try require(ClaudeSessionScanner.read(file: file))
        do {
            _ = try ClaudeSessionRenamer.rename(corruptRecord, to: "不得覆盖", root: root)
            preconditionFailure("未拒绝损坏名称文件")
        } catch { }
        precondition(tryData(sidecar) == Data("损坏数据".utf8))
        precondition(tryData(file) == source)
        try Data("{\"customTitle\":\"客户端新名称\",\"extra\":42}".utf8).write(to: sidecar)
        do {
            _ = try ClaudeSessionRenamer.rename(record, to: "过期写入", root: root)
            preconditionFailure("未拒绝过期记录")
        } catch is ClaudeSessionRenamer.RenameError { }
        let refreshed = try require(ClaudeSessionScanner.read(file: file))
        _ = try ClaudeSessionRenamer.rename(refreshed, to: "保留元数据", root: root)
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as! [String: Any]
        precondition(metadata["extra"] as? Int == 42)
        let inlineSource = Data("{\"sessionId\":\"\(id)\",\"cwd\":\"/tmp\",\"customTitle\":\"正文名称\"}\n".utf8)
        try inlineSource.write(to: file)
        let inlineRecord = try require(ClaudeSessionScanner.read(file: file))
        let inlineUpdated = try ClaudeSessionRenamer.rename(inlineRecord, to: "侧文件新名称", root: root)
        precondition(inlineUpdated.name == "侧文件新名称")
        precondition(tryData(file) == inlineSource)
        let inlineSidecar = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as! [String: Any]
        precondition(inlineSidecar["customTitle"] as? String == "侧文件新名称")
        try source.write(to: file)
        try manager.removeItem(at: sidecar)
        let outside = root.appendingPathComponent("outside.json")
        try Data("{}".utf8).write(to: outside)
        try manager.createSymbolicLink(at: sidecar, withDestinationURL: outside)
        let linkedRecord = try require(ClaudeSessionScanner.read(file: file))
        do {
            _ = try ClaudeSessionRenamer.rename(linkedRecord, to: "越界链接", root: root)
            preconditionFailure("未拒绝软链接")
        } catch is ClaudeSessionRenamer.RenameError { }
        precondition(tryData(outside) == Data("{}".utf8))
        print("改名检查通过：中文、再次改名、备份、错误根目录、损坏保留、正文不变、过期拒绝、元数据保留、内嵌名称按原包写侧文件、软链接拒绝；仅临时数据")
    }
    static func require(_ record: ClaudeSessionRecord?) throws -> ClaudeSessionRecord {
        guard let record else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }
    static func tryData(_ file: URL) -> Data { try! Data(contentsOf: file) }
}
