import AppKit
import SwiftUI

/// Claude Code 终端右上角的朗读入口与播放状态。
struct VoiceOverlay: View {
    @ObservedObject var surfaceView: Ghostty.SurfaceView
    @StateObject private var model = VoiceOverlayModel()
    @ObservedObject private var controller = VoiceController.shared
    @ObservedObject private var player = VoiceController.shared.playback
    @State private var scrubbing: Double?

    var body: some View {
        Group {
            if controller.settings.isEnabled, controller.settings.isOverlayShown, model.isVisible {
                VStack {
                    HStack {
                        Spacer()
                        controls
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 2)
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .onAppear { model.update(pwd: surfaceView.pwd) }
        .onChange(of: surfaceView.pwd) { model.update(pwd: $0) }
    }

    @ViewBuilder private var controls: some View {
        if controller.isPreparing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).frame(width: 18, height: 18)
                Text(controller.isRewriting ? "正在改写口播稿…" : "正在合成音频…").font(.caption)
                Button { controller.stop() } label: { Image(systemName: "stop.fill") }
                    .help("停止朗读")
                historyButton
            }
            .buttonStyle(.borderless)
        } else if player.isActive {
            HStack(spacing: 8) {
                Button { player.togglePause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                }
                .help(player.isPaused ? "继续朗读" : "暂停朗读")
                Button { controller.stop() } label: { Image(systemName: "stop.fill") }
                    .help("停止朗读")
                Text(timeText(scrubbing ?? player.position) + " / " + timeText(player.duration))
                    .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { scrubbing ?? player.position },
                    set: { scrubbing = $0 }
                ), in: 0...max(player.duration, 0.001), onEditingChanged: { editing in
                    if editing { scrubbing = player.position }
                    else if let target = scrubbing { try? player.seek(to: target); scrubbing = nil }
                })
                .frame(width: 90)
                .accessibilityLabel("朗读进度")
                Button { cycleRate() } label: {
                    Text(String(format: "%gx", controller.settings.rate)).monospacedDigit()
                }
                .help("倍速（点一下换下一档）")
                historyButton
            }
            .buttonStyle(.borderless)
        } else {
            HStack(spacing: 8) {
                Button { speakLatest() } label: { Image(systemName: "speaker.wave.2.fill") }
                    .help("朗读 Claude 最新回复（⌥⌘S）")
                Divider().frame(height: 18)
                historyButton
            }
            .buttonStyle(.borderless)
        }
    }

    private var historyButton: some View {
        Button { (NSApp.delegate as? AppDelegate)?.showVoiceTranscript() } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .help("打开朗读记录（看稿子、拖进度、回听历史）")
    }

    private func speakLatest() {
        let pwd = surfaceView.pwd
        VoiceController.shared.speakLatestReply(cwd: pwd, terminalTitle: surfaceView.title) { [weak surfaceView] in
            surfaceView?.window != nil && surfaceView?.pwd == pwd
        }
    }

    private func cycleRate() {
        let rates = [0.75, 1.0, 1.25, 1.5, 2.0]
        let next = rates.first(where: { $0 > controller.settings.rate + 0.001 }) ?? rates[0]
        controller.settings.rate = next
    }

    private func timeText(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

@MainActor
private final class VoiceOverlayModel: ObservableObject {
    @Published private(set) var isVisible = false
    private var pwd: String?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    deinit { timer?.invalidate() }

    func update(pwd: String?) {
        self.pwd = pwd
        check()
    }

    private func check() {
        guard let pwd, pwd.hasPrefix("/") else { isVisible = false; return }
        Task {
            let active = await Task.detached(priority: .utility) {
                ClaudeSessionProcesses.snapshot().isActive(directory: pwd)
            }.value
            guard self.pwd == pwd else { return }
            isVisible = active
        }
    }
}
