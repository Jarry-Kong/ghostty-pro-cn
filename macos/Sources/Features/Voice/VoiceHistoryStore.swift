import Foundation
import Darwin

/// 朗读历史的本地 JSON 存储。
final class VoiceHistoryStore {
    // ponytail: 进程内全局互斥保证 lockf 的同进程语义；多索引并发成为瓶颈时再按路径拆分。
    private static let processLock = NSLock()
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let directory = supportDirectory?.appendingPathComponent("Ghostty-Recovered", isDirectory: true)
        self.fileURL = fileURL ?? directory?.appendingPathComponent("voice-history.json")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voice-history.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [VoiceHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([VoiceHistoryEntry].self, from: Data(contentsOf: fileURL))
    }

    func save(_ entries: [VoiceHistoryEntry]) throws {
        try withExclusiveAccess { try saveUnlocked(entries) }
    }

    /// 不等待其他进程的写锁，避免主线程无限阻塞；冲突由界面明确提示。
    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        guard Self.processLock.try() else {
            throw NSError(domain: "Ghostty.AudioHistory", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "朗读历史正在修改，请稍后重试"])
        }
        defer { Self.processLock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.standardizedFileURL.path else {
            throw CocoaError(.fileWriteNoPermission)
        }
        // 未创建的末级目录无法完整解析软链接，先核对最近的既有父节点。
        var ancestor = directory.standardizedFileURL
        while true {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: ancestor.path) {
                let kind = attributes[.type] as? FileAttributeType
                let normalSystemAlias = ["/tmp", "/var", "/etc"].contains(ancestor.path)
                guard kind == .typeDirectory || (kind == .typeSymbolicLink && normalSystemAlias),
                      ancestor.resolvingSymlinksInPath().standardizedFileURL.path == ancestor.standardizedFileURL.path else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                break
            }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { throw CocoaError(.fileWriteNoPermission) }
            ancestor = parent
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(".voice-history.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
            throw NSError(domain: "Ghostty.AudioHistory", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "另一进程正在修改朗读历史，请稍后重试"])
        }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }
        return try body()
    }

    /// 仅供已经持有同一索引写锁的成套音频事务调用。
    func saveUnlocked(_ entries: [VoiceHistoryEntry]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".voice-history-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: staging) }
        try encoder.encode(entries).write(to: staging, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        var protected = staging
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try protected.setResourceValues(resources)
        guard Darwin.rename(staging.path, fileURL.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
