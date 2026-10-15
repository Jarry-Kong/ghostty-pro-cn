import AppKit
import SwiftUI

enum ClaudeSessionOpenMode: String, CaseIterable, Identifiable {
    static let maximumSplits = 5
    case tabsInCurrentWindow, tabsInNewWindow, separateWindows, splitsInNewWindow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tabsInCurrentWindow: return "在当前窗口开标签页"
        case .tabsInNewWindow: return "开一个新窗口装下"
        case .separateWindows: return "每个各开一个窗口"
        case .splitsInNewWindow: return "新窗口里分成几列"
        }
    }
}

@MainActor
final class SessionLibraryWindowController: NSWindowController {
    private let model = SessionLibraryModel()
    private var isOpening = false
    // 窗口引用只用于切换；是否仍运行以进程快照为依据。
    private static var opened: [String: WeakTerminal] = [:]
    private final class WeakTerminal {
        weak var terminal: TerminalController?
        weak var surface: Ghostty.SurfaceView?
        var didObserveProcess = false
        var observedPID: Int32?
        init(_ terminal: TerminalController, surface: Ghostty.SurfaceView?) {
            self.terminal = terminal
            self.surface = surface
        }
    }
    init() {
        super.init(window: nil)
        model.onProcessSnapshot = { snapshot in
            for (id, entry) in Self.opened where snapshot.ownedSessions.contains(id.lowercased()) {
                if entry.observedPID == nil { entry.observedPID = snapshot.sessions[id.lowercased()] }
                entry.didObserveProcess = true
            }
        }
        // 无界面归档的控制器不会自动调用 loadWindow，必须明确创建窗口。
        loadWindow()
    }
    required init?(coder: NSCoder) { fatalError("不支持从归档创建") }
    override func loadWindow() {
        let view = SessionLibraryView(model: model, onOpen: { [weak self] records, mode in
            self?.open(records, mode: mode)
        }, onClose: { [weak self] in self?.close() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "历史会话"
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        self.window = window
    }
    private func open(_ records: [ClaudeSessionRecord], mode: ClaudeSessionOpenMode) {
        guard !isOpening else { return }
        isOpening = true
        Task {
            defer { isOpening = false }
            let snapshot = await Task.detached(priority: .userInitiated) { ClaudeSessionProcesses.snapshot() }.value
            openValidated(records, mode: mode, snapshot: snapshot)
        }
    }
    private func openValidated(_ records: [ClaudeSessionRecord], mode: ClaudeSessionOpenMode,
                               snapshot: ClaudeSessionProcesses.Snapshot) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        if mode == .splitsInNewWindow && records.count > ClaudeSessionOpenMode.maximumSplits {
            showError("分列最多打开 5 个会话，请改用标签页或分别开窗。")
            return
        }
        // 先验证整批，避免前几个已启动，后续才发现坏目录。
        for record in records {
            if snapshot.sessions[record.id.lowercased()] == nil && snapshot.isUncertain(directory: record.workingDirectory) {
                showError("当前目录存在无法确认编号的 Claude 进程，或运行状态检查失败。为避免重复打开，请先确认其他终端中的会话状态。")
                return
            }
            var isDirectory: ObjCBool = false
            let directoryExists = FileManager.default.fileExists(atPath: record.workingDirectory, isDirectory: &isDirectory)
            guard record.isValidResumeID && (snapshot.sessions[record.id.lowercased()] != nil ||
                (directoryExists && isDirectory.boolValue)) else {
                showError("会话目录不存在，或会话编号含无效字符。")
                return
            }
        }
        var parent = mode == .tabsInCurrentWindow ? TerminalController.lastMain : nil
        for record in records {
            let isRunning = snapshot.sessions[record.id.lowercased()] != nil
            if let entry = Self.opened[record.id], let existing = entry.terminal, let surface = entry.surface,
               existing.surfaceTree.root?.node(view: surface) != nil, let window = existing.window,
               NSApp.windows.contains(window) {
                let owned = snapshot.ownedSessions.contains(record.id.lowercased())
                let currentPID = snapshot.sessions[record.id.lowercased()]
                if isRunning && owned && entry.observedPID == nil {
                    entry.observedPID = currentPID
                    entry.didObserveProcess = true
                }
                // 启动尚未观察到进程时不重复提交命令；启动失败可关闭该终端后重试。
                if (isRunning && owned && entry.observedPID == currentPID) || (!isRunning && !entry.didObserveProcess) {
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    existing.focusedSurfaceDidChange(to: surface)
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(surface)
                    continue
                }
                if !isRunning { Self.opened.removeValue(forKey: record.id) }
            }
            if isRunning {
                showError("这个会话正在其他终端或窗口中运行，没有重复打开。请切到已经运行的会话。")
                continue
            }
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = record.workingDirectory
            config.initialInput = record.resumeCommand + "\n"
            let terminal: TerminalController
            let openedSurface: Ghostty.SurfaceView?
            if mode == .splitsInNewWindow, let current = parent, let surface = current.focusedSurface {
                guard let split = current.newSplit(at: surface, direction: .right, baseConfig: config) else {
                    showError("创建分列失败。"); return
                }
                terminal = current
                openedSurface = split
            } else if mode != .separateWindows, let current = parent {
                guard let tab = TerminalController.newTab(delegate.ghostty, from: current.window, withBaseConfig: config) else { return }
                terminal = tab
                openedSurface = tab.focusedSurface ?? tab.surfaceTree.first
            } else {
                terminal = TerminalController.newWindow(delegate.ghostty, withBaseConfig: config)
                openedSurface = terminal.focusedSurface ?? terminal.surfaceTree.first
            }
            if mode != .splitsInNewWindow || parent == nil { terminal.titleOverride = record.name }
            Self.opened[record.id] = WeakTerminal(terminal, surface: openedSurface)
            if parent == nil { parent = terminal }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self?.model.reload()
        }
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "无法恢复会话"
        alert.informativeText = text
        alert.runModal()
    }
}
