import AppKit
import XCTest
@testable import Ghostty

final class RecoveredWindowTests: XCTestCase {
    func testOriginalSplitLimit() { XCTAssertEqual(ClaudeSessionOpenMode.maximumSplits, 5) }
    @MainActor
    func testRestoredMenusMatchOriginalPlacementWithoutDuplicates() throws {
        let main = NSMenu()
        let file = NSMenu(title: "文件")
        file.addItem(withTitle: "新建窗口", action: nil, keyEquivalent: "")
        file.addItem(withTitle: "新建标签页", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for menu in [file, edit] {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        let delegate = AppDelegate()
        delegate.setupRecoveredFeaturesMenu(in: main, speechEnabled: true)
        delegate.setupRecoveredFeaturesMenu(in: main, speechEnabled: true)
        XCTAssertEqual(file.items.map(\.title), ["新建窗口", "新建标签页", "历史会话…"])
        XCTAssertFalse(main.items.contains { $0.title == "恢复功能" })
        XCTAssertEqual(edit.items.filter { $0.title == "朗读" }.count, 1)
        let speech = try XCTUnwrap(edit.items.first?.submenu)
        XCTAssertEqual(speech.items.map(\.title), ["朗读 Claude 最新回复", "朗读选中内容", "停止朗读", "朗读记录…", "语音朗读设置…"])
        XCTAssertEqual(speech.items.first?.keyEquivalent, "s")
        XCTAssertEqual(speech.items.first?.keyEquivalentModifierMask, [.option, .command])
        XCTAssertTrue(speech.items.allSatisfy { $0.target === delegate && $0.action != nil })
    }

    @MainActor
    func testDisabledSpeechKeepsSettingsAndCanReenableWithoutDuplicates() {
        let main = NSMenu()
        let menus = [NSMenu(title: "Ghostty"), NSMenu(title: "文件"), NSMenu(title: "编辑")]
        for menu in menus {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        let delegate = AppDelegate()
        for enabled in [true, false, false, true, true, false] {
            delegate.setupRecoveredFeaturesMenu(in: main, speechEnabled: enabled)
            XCTAssertEqual(menus[2].items.filter { $0.title == "朗读" }.count, enabled ? 1 : 0)
            XCTAssertEqual(menus[0].items.filter { $0.title == "语音朗读设置…" }.count, enabled ? 0 : 1)
            XCTAssertEqual(menus[1].items.filter { $0.title == "历史会话…" }.count, 1)
        }
    }

    @MainActor
    func testSessionWindowExistsBeforePresentation() throws {
        let controller = SessionLibraryWindowController()
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(controller.isWindowLoaded)
        XCTAssertEqual(window.title, "历史会话")
        XCTAssertNotNil(window.contentViewController)
        controller.close()
    }

    @MainActor
    func testVoiceWindowsExistBeforePresentation() throws {
        let settings = VoiceSettingsWindowController()
        XCTAssertEqual(try XCTUnwrap(settings.window).title, "语音设置")
        let history = VoiceTranscriptWindowController()
        XCTAssertEqual(try XCTUnwrap(history.window).title, "语音朗读历史")
        settings.close()
        history.close()
    }
}
