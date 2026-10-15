import Foundation
import Combine

@MainActor
final class SessionLibraryModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all, recent, idle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .recent: return "近 7 天"
            case .idle: return "没在跑的"
            }
        }
    }
    @Published var records: [ClaudeSessionRecord] = []
    @Published var keyword = ""
    @Published var selection: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var filter = Filter.all
    @Published var isRenaming = false
    private(set) var referenceDate = Date()
    var onProcessSnapshot: (@MainActor (ClaudeSessionProcesses.Snapshot) -> Void)?
    private let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.root = root
    }

    func rename(_ record: ClaudeSessionRecord, to title: String) async -> Bool {
        guard !isRenaming, !isLoading else { return false }
        isRenaming = true
        defer { isRenaming = false }
        let root = root
        do {
            let updated = try await Task.detached(priority: .userInitiated) {
                try ClaudeSessionRenamer.rename(record, to: title, root: root)
            }.value
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                // 保留当前进程信息，不把纯名称扫描的默认状态当作退出。
                var replacement = updated
                replacement.runningPID = records[index].runningPID
                replacement.runningStateUnknown = records[index].runningStateUnknown
                records[index] = replacement
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "改名没成功：\(error.localizedDescription)"
            return false
        }
    }
    var visibleRecords: [ClaudeSessionRecord] {
        visibleRecords(at: referenceDate)
    }
    func visibleRecords(at now: Date) -> [ClaudeSessionRecord] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .recent: matchesFilter = record.lastActivity >= now.addingTimeInterval(-604800)
            case .idle: matchesFilter = !record.isRunning && !record.runningStateUnknown
            }
            return matchesFilter && (query.isEmpty || [record.name ?? "", record.workingDirectory, record.preview]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    var selectedRecords: [ClaudeSessionRecord] { records.filter { selection.contains($0.id) } }
    func selectAllVisible() {
        selection.formUnion(visibleRecords.filter { !$0.isRunning && !$0.runningStateUnknown }.map(\.id))
    }
    var groupedRecords: [(title: String, items: [ClaudeSessionRecord])] {
        var groups: [(String, [ClaudeSessionRecord])] = []
        for record in visibleRecords {
            let title = Self.groupTitle(for: record.lastActivity, now: referenceDate)
            if let index = groups.firstIndex(where: { $0.0 == title }) { groups[index].1.append(record) }
            else { groups.append((title, [record])) }
        }
        return groups
    }
    static func groupTitle(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "昨天" }
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days <= 6 { return "最近 7 天" }
        // 原包按日龄分组；标签虽然写“本月”，并非自然月，先保持原行为。
        return days <= 29 ? "本月更早" : "更早"
    }
    func reload() async {
        guard !isLoading, !isRenaming else { return }
        isLoading = true
        defer { isLoading = false }
        let root = root
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let snapshot = ClaudeSessionProcesses.snapshot()
                let records = try ClaudeSessionScanner.scan(root: root).map { source in
                    var record = source
                    record.runningPID = snapshot.sessions[source.id.lowercased()]
                    record.runningStateUnknown = record.runningPID == nil && snapshot.isUncertain(directory: source.workingDirectory)
                    return record
                }
                return (records, snapshot)
            }.value
            records = result.0
            onProcessSnapshot?(result.1)
            referenceDate = Date()
            selection.formIntersection(Set(records.map(\.id)))
            errorMessage = nil
        } catch { errorMessage = "扫描会话失败：\(error.localizedDescription)" }
    }
}
