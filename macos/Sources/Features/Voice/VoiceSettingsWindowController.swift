import AppKit
import SwiftUI

/// 语音设置窗口控制器。
@MainActor
final class VoiceSettingsWindowController: NSWindowController {
    private var settings: VoiceSettings

    init(settings: VoiceSettings = VoiceSettings()) {
        self.settings = settings
        super.init(window: nil)
        // 无界面归档时明确创建窗口，避免菜单响应却没有窗口显示。
        loadWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this window")
    }

    override func loadWindow() {
        let view = VoiceSettingsView(settings: Binding(
            get: { VoiceController.shared.settings },
            set: { VoiceController.shared.settings = $0 }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 510),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "语音设置"
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        self.window = window
    }
}
