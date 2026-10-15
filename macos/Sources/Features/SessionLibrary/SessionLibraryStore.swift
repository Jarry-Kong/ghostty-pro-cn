import Foundation

/// 历史会话的本地 JSON 存储。
/// 文件名沿用安装包中发现的 `session.json` 线索，具体旧格式兼容逻辑待后续补齐。
final class SessionLibraryStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let directory = supportDirectory?.appendingPathComponent("Ghostty-Recovered", isDirectory: true)
        self.fileURL = fileURL ?? directory?.appendingPathComponent("session.json")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("session.json")

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [SessionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([SessionRecord].self, from: Data(contentsOf: fileURL))
    }

    func save(_ records: [SessionRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
