import SwiftUI

/// 语义朗读转录和历史记录窗口。
struct VoiceTranscriptView: View {
    @ObservedObject var controller = VoiceController.shared
    @State private var selectedHistoryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("语音朗读历史").font(.title2.weight(.semibold))
                Spacer()
                Button("读取旧录音目录…") { controller.chooseOriginalHistoryRoot() }
                    .disabled(controller.isUpdatingHistory)
            }.padding()

            Divider()
            if let notice = controller.rewriteNotice { Text(notice).font(.caption).foregroundColor(.secondary).padding(.horizontal) }
            SpeechPlaybackControls(player: controller.playback, rate: $controller.settings.rate,
                                   isPreparing: controller.isPreparing, onStop: controller.stop,
                                   fallbackNotice: controller.fallbackNotice, isRewriting: controller.isRewriting)
            Divider()

            if controller.unreadableOriginalRecordings > 0 {
                Text("原版有 \(controller.unreadableOriginalRecordings) 条记录无法读取，原文件未修改。")
                    .font(.caption).foregroundColor(.orange).padding(.horizontal)
            }
            if controller.entries.isEmpty && controller.originalRecordings.isEmpty && controller.transcriptSegments.isEmpty {
                Label("暂无朗读记录", systemImage: "speaker.wave.2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selectedHistoryID) {
                        if !controller.transcriptSegments.isEmpty {
                            Label("当前稿件", systemImage: "doc.text")
                                .tag(Optional<UUID>.none)
                        }
                        Section("本版本记录") {
                            ForEach(controller.entries) { entry in
                                HistoryRow(entry: entry) { controller.playHistory(entry) }
                                    .tag(Optional(entry.id))
                                    .contextMenu {
                                        Button("播放") { controller.playHistory(entry) }
                                        Button("在访达中显示") { controller.revealHistory(entry) }
                                            .disabled(!entry.hasRecordedAudio)
                                        Divider()
                                        Button("移到废纸篓…") { controller.deleteHistory(entry) }
                                            .disabled(!entry.hasRecordedAudio)
                                    }
                            }
                        }
                        if !controller.originalRecordings.isEmpty {
                            Section("原版录音（只读）") {
                                ForEach(controller.originalRecordings) { recording in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(recording.record.summary).lineLimit(2)
                                            if recording.record.projectName != nil || recording.record.terminalTitle != nil {
                                                Text([recording.record.projectName, recording.record.terminalTitle]
                                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                                    .lineLimit(1).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Text("\(recording.record.createdAt.formatted(date: .numeric, time: .shortened)) · \(recording.record.segments.count) 段 · \(Self.durationText(recording.record.totalDuration))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("导入") { controller.importOriginalHistory(recording) }
                                            .disabled(controller.isUpdatingHistory)
                                        Button("播放") {
                                            selectedHistoryID = nil
                                            controller.playOriginalHistory(recording)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 230, idealWidth: 260)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 8) {
                            Divider()
                            HStack {
                                Text("\(controller.entries.count) 条 · \(Self.sizeText(controller.historyBytes))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            HStack {
                                Button("刷新") { controller.reloadHistory() }
                                    .disabled(controller.isUpdatingHistory)
                                    .help("从废纸篓找回录音后，刷新可恢复其索引")
                                Spacer()
                                Button("清空…") { controller.clearHistory() }
                                    .disabled(controller.isUpdatingHistory || !controller.entries.contains(where: \.hasRecordedAudio))
                            }
                        }
                        .padding(.horizontal).padding(.bottom, 8)
                        .background(.bar)
                    }

                    if let entry = controller.entries.first(where: { $0.id == selectedHistoryID }) {
                        TranscriptSegmentList(
                            segments: entry.segments.isEmpty ? [SpeechSegment(text: entry.text)] : entry.segments,
                            currentIndex: controller.playingHistoryID == entry.id ? controller.playback.currentIndex : nil,
                            onSelect: { controller.playHistory(entry, startingAt: $0) }
                        )
                    } else {
                        TranscriptSegmentList(
                            segments: controller.transcriptSegments,
                            currentIndex: controller.playingHistoryID == nil && controller.playback.isActive
                                ? controller.playback.currentIndex : nil,
                            onSelect: controller.jumpToTranscriptSegment
                        )
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 360)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .task { controller.reloadHistory(restoreRecoveredIndex: false) }
    }

    private static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct TranscriptSegmentList: View {
    let segments: [SpeechSegment]
    let currentIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: currentIndex == index ? "speaker.wave.2.fill" : "circle")
                                .frame(width: 18)
                                .foregroundStyle(currentIndex == index ? Color.accentColor : .secondary)
                            Text(segment.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let end = segment.endTime {
                                Text(Self.timeText(end))
                                    .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal).padding(.vertical, 9)
                        .background(currentIndex == index ? Color.accentColor.opacity(0.1) : .clear)
                        .onTapGesture { onSelect(index) }
                        .help("点一下从这一段开始念")
                        .accessibilityAddTraits(.isButton)
                        .id(index)
                    }
                }
            }
            .onChange(of: currentIndex) { index in
                if let index { withAnimation { proxy.scrollTo(index, anchor: .center) } }
            }
        }
    }

    private static func timeText(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
