import Foundation

/// 只计算清理目标，不删除数据；实际清理必须另有用户授权。
enum VoiceHistoryRetention {
    static let defaultCount = 50
    // 原包 applyHistoryLimits 在 0x10015ca70 左移 20 位，MB 按 1024×1024 换算。
    static let defaultBytes: Int64 = 300 * 1024 * 1024

    struct Item {
        let id: UUID
        let createdAt: Date
        let bytes: Int64
    }

    static func removals(_ items: [Item], maxCount: Int = defaultCount,
                         maxBytes: Int64 = defaultBytes) throws -> [UUID] {
        guard maxCount >= 0, maxBytes >= 0,
              Set(items.map(\.id)).count == items.count else { throw CocoaError(.fileReadCorruptFile) }
        var total: Int64 = 0
        for item in items {
            guard item.bytes >= 0 else { throw CocoaError(.fileReadCorruptFile) }
            let sum = total.addingReportingOverflow(item.bytes)
            guard !sum.overflow else { throw CocoaError(.fileReadTooLarge) }
            total = sum.partialValue
        }
        // 存储索引按新到旧排列；ISO 日期可能只有秒精度，同秒时仍先清理靠后的旧记录。
        let oldest = items.enumerated().sorted {
            $0.element.createdAt == $1.element.createdAt ? $0.offset > $1.offset : $0.element.createdAt < $1.element.createdAt
        }.map(\.element)
        var count = items.count
        var removed: [UUID] = []
        for item in oldest {
            if count <= maxCount && total <= maxBytes { break }
            removed.append(item.id)
            count -= 1
            total -= item.bytes
        }
        return removed
    }
}
