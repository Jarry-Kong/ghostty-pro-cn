import Foundation

/// 历史会话的可持久化记录。字段会随着逆向分析结果逐步补齐。
struct SessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var directory: String?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String,
        directory: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.directory = directory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }
}
