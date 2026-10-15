import SwiftUI

struct SpeechPlaybackControls: View {
    @ObservedObject var player: SegmentedSpeechPlayer
    @Binding var rate: Double
    var isPreparing: Bool
    var onStop: () -> Void
    var fallbackNotice: String? = nil
    var isRewriting = false
    @State private var isSeeking = false
    @State private var seekPreview: Double = 0
    @State private var seekError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fallbackNotice { Text(fallbackNotice).font(.caption).foregroundColor(.secondary) }
            if isPreparing { ProgressView(isRewriting ? "正在改写口播稿…" : "正在合成音频…") }
            HStack {
                Button(player.isPaused ? "继续" : "暂停") { player.togglePause() }
                    .disabled(!player.isActive)
                Button("停止", action: onStop).disabled(!player.isActive && !isPreparing)
                Picker("倍速", selection: $rate) {
                    ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
                        Text(String(format: "%g 倍", speed)).tag(speed)
                    }
                }.frame(width: 160)
                Spacer()
                Text(timeText(isSeeking ? seekPreview : player.position) + " / " + timeText(player.duration))
                    .monospacedDigit().font(.caption)
            }
            Slider(value: Binding(
                get: { isSeeking ? seekPreview : player.position },
                set: { seekPreview = $0 }
            ), in: 0...max(player.duration, 0.001), onEditingChanged: { editing in
                isSeeking = editing
                if editing { seekPreview = player.position }
                else {
                    do { try player.seek(to: seekPreview); seekError = nil }
                    catch { seekError = "定位失败：\(error.localizedDescription)" }
                }
            }).accessibilityLabel("朗读进度").disabled(player.duration <= 0 || isPreparing)
            if let error = seekError ?? player.errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }.padding()
    }

    private func timeText(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
