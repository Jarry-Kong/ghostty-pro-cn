import SwiftUI

/// 朗读历史中的一行。
struct HistoryRow: View {
    let entry: VoiceHistoryEntry
    var onPlay: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displaySummary)
                    .lineLimit(2)
                if entry.projectName != nil || entry.terminalTitle != nil {
                    Text([entry.projectName, entry.terminalTitle]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .lineLimit(1).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    Text(entry.createdAt, style: .relative)
                    if !entry.segments.isEmpty {
                        Text("· \(entry.segments.count) 段")
                        if entry.totalDuration > 0 {
                            Text("· \(Self.durationText(entry.totalDuration))")
                        }
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("播放", action: { onPlay?() })
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
