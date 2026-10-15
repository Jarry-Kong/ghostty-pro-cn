import AppKit
import SwiftUI

/// 朗读历史窗口控制器。
@MainActor
final class VoiceTranscriptWindowController: NSWindowController {
    private let entries: [VoiceHistoryEntry]

    init(entries: [VoiceHistoryEntry] = []) {
        self.entries = entries
        super.init(window: nil)
        // 无界面归档时明确创建窗口，避免菜单响应却没有窗口显示。
        loadWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this window")
    }

    override func loadWindow() {
        let view = VoiceTranscriptView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "语音朗读历史"
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        self.window = window
    }
}
