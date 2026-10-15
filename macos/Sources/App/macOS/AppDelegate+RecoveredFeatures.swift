import AppKit

// MARK: - 恢复功能入口

@MainActor extension AppDelegate {
    /// 根据原包真实菜单取证挂载入口；不再增加独立的临时菜单。
    func setupRecoveredFeaturesMenu(in explicitMenu: NSMenu? = nil, speechEnabled: Bool? = nil) {
        guard let mainMenu = explicitMenu ?? NSApp.mainMenu,
              let fileMenu = mainMenu.items.first(where: { $0.title == "文件" || $0.title == "File" })?.submenu,
              let editMenu = mainMenu.items.first(where: { $0.title == "编辑" || $0.title == "Edit" })?.submenu else {
            AppDelegate.logger.error("恢复入口挂载失败：未找到文件或编辑菜单")
            return
        }
        if !fileMenu.items.contains(where: { $0.action == #selector(showSessionLibrary(_:)) }) {
            let sessionItem = NSMenuItem(title: "历史会话…", action: #selector(showSessionLibrary(_:)), keyEquivalent: "")
            sessionItem.target = self
            // 原包入口位于新建窗口、新建标签页之后。
            fileMenu.insertItem(sessionItem, at: min(2, fileMenu.numberOfItems))
        }
        if let old = editMenu.items.first(where: { $0.identifier?.rawValue == "recovered.speech" }) {
            editMenu.removeItem(old)
        }
        let firstMenu = mainMenu.items.first?.submenu
        let appMenu = firstMenu === fileMenu || firstMenu === editMenu ? nil : firstMenu
        if let old = appMenu?.items.first(where: { $0.identifier?.rawValue == "recovered.speech.settings" }) {
            appMenu?.removeItem(old)
        }
        guard speechEnabled ?? VoiceController.shared.settings.isEnabled else {
            let settingsItem = NSMenuItem(title: "语音朗读设置…", action: #selector(showVoiceSettings(_:)), keyEquivalent: "")
            settingsItem.identifier = NSUserInterfaceItemIdentifier("recovered.speech.settings")
            settingsItem.target = self
            appMenu?.addItem(settingsItem)
            return
        }
        let speechMenu = NSMenu(title: "朗读")
        for (title, action) in [
            ("朗读 Claude 最新回复", #selector(speakLatestClaudeReply(_:))),
            ("朗读选中内容", #selector(speakSelectedText(_:))),
            ("停止朗读", #selector(stopVoice(_:))),
            ("朗读记录…", #selector(showVoiceTranscript(_:))),
            ("语音朗读设置…", #selector(showVoiceSettings(_:)))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if action == #selector(speakLatestClaudeReply(_:)) {
                item.keyEquivalent = "s"
                item.keyEquivalentModifierMask = [.option, .command]
            }
            speechMenu.addItem(item)
        }
        let parent = NSMenuItem(title: "朗读", action: nil, keyEquivalent: "")
        parent.identifier = NSUserInterfaceItemIdentifier("recovered.speech")
        parent.submenu = speechMenu
        editMenu.addItem(parent)
    }

    @objc func speakSelectedText(_ sender: Any?) {
        guard let terminal = TerminalController.lastMain,
              let surface = terminal.focusedSurface,
              let text = surface.accessibilitySelectedText() else { return }
        VoiceController.shared.speak(text, summary: "选中内容",
            projectName: surface.pwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            terminalTitle: surface.title)
    }

    @objc func speakLatestClaudeReply(_ sender: Any?) {
        guard let terminal = TerminalController.lastMain, let surface = terminal.focusedSurface else { return }
        VoiceController.shared.speakLatestReply(cwd: surface.pwd, terminalTitle: surface.title) {
            TerminalController.lastMain === terminal && terminal.focusedSurface === surface
        }
    }

    @objc func toggleVoicePause(_ sender: Any?) { VoiceController.shared.togglePause() }
    @objc func stopVoice(_ sender: Any?) { VoiceController.shared.stop() }

    @objc func saveCurrentSession(_ sender: Any?) {
        guard let terminal = TerminalController.lastMain, let window = terminal.window else { return }
        let store = SessionLibraryStore()
        do {
            var records = try store.load()
            records.insert(SessionRecord(title: terminal.titleOverride ?? window.title,
                                         directory: terminal.focusedSurface?.pwd), at: 0)
            try store.save(records)
        } catch {
            let alert = NSAlert()
            alert.messageText = "保存会话失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// 显示历史会话管理窗口。
    @objc func showSessionLibrary(_ sender: Any? = nil) {
        recoveredWindowControllers.removeAll { $0 is SessionLibraryWindowController && $0.window?.isVisible != true }
        if let existing = recoveredWindowControllers.first(where: { $0 is SessionLibraryWindowController && $0.window?.isVisible == true }) {
            existing.window?.makeKeyAndOrderFront(sender)
            return
        }
        let controller = SessionLibraryWindowController()
        recoveredWindowControllers.append(controller)
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
    }

    /// 显示语音设置窗口。
    @objc func showVoiceSettings(_ sender: Any? = nil) {
        if let existing = recoveredWindowControllers.first(where: { $0 is VoiceSettingsWindowController }) {
            existing.showWindow(sender)
            return
        }
        let controller = VoiceSettingsWindowController()
        recoveredWindowControllers.append(controller)
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
    }

    /// 显示语音朗读历史窗口。
    @objc func showVoiceTranscript(_ sender: Any? = nil) {
        if let existing = recoveredWindowControllers.first(where: { $0 is VoiceTranscriptWindowController }) {
            existing.showWindow(sender)
            return
        }
        let controller = VoiceTranscriptWindowController()
        recoveredWindowControllers.append(controller)
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
    }
}
