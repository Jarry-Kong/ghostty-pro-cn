import Foundation

@main
enum HistoryRetentionCheck {
    static func main() throws {
        let first = VoiceHistoryRetention.Item(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), bytes: 100)
        let second = VoiceHistoryRetention.Item(id: UUID(), createdAt: Date(timeIntervalSince1970: 2), bytes: 100)
        let boundary = try VoiceHistoryRetention.removals([second, first], maxCount: 2, maxBytes: 200)
        precondition(boundary.isEmpty)
        let count = try VoiceHistoryRetention.removals([second, first], maxCount: 1, maxBytes: 200)
        let bytes = try VoiceHistoryRetention.removals([second, first], maxCount: 2, maxBytes: 199)
        precondition(count == [first.id] && bytes == [first.id])
        let zero = try VoiceHistoryRetention.removals([second, first], maxCount: 0, maxBytes: 0)
        precondition(zero == [first.id, second.id])
        do { _ = try VoiceHistoryRetention.removals([first, first]); preconditionFailure("重复编号未拒绝") } catch { }
        let huge = VoiceHistoryRetention.Item(id: UUID(), createdAt: Date(), bytes: Int64.max)
        do { _ = try VoiceHistoryRetention.removals([huge, first]); preconditionFailure("容量溢出未拒绝") } catch { }
        precondition(VoiceHistoryRetention.defaultCount == 50 && VoiceHistoryRetention.defaultBytes == 314_572_800)
        let fiftyOne = (0..<51).map { VoiceHistoryRetention.Item(id: UUID(), createdAt: Date(timeIntervalSince1970: Double($0)), bytes: 0) }
        let fifty = try VoiceHistoryRetention.removals(Array(fiftyOne.prefix(50)))
        let fiftyOneRemoved = try VoiceHistoryRetention.removals(fiftyOne)
        precondition(fifty.isEmpty && fiftyOneRemoved == [fiftyOne[0].id])
        let sameSecond = VoiceHistoryRetention.Item(id: UUID(), createdAt: first.createdAt, bytes: 100)
        let tied = try VoiceHistoryRetention.removals([sameSecond, first], maxCount: 1, maxBytes: 200)
        precondition(tied == [first.id])
        print("历史限额检查通过：原版 50／300 默认值、等于上限保留、超限最旧优先、双限额、重复及溢出拒绝；无数据删除")
    }
}
