# 开发日志 DEVLOG

> 创建于 2026-06-04 · 最后更新 2026-06-22
>
> 按时间倒序排列，最新条目在最上方。
> 每条记录：任务简述、变更内容、技术决策（可选）、已知问题（可选）。

---

## 2026-06-22 · 修复"切窗口后顶部一大片空白"问题

**任务简述**
针对用户反馈的"把窗口拖到一边/切到其他 app 再切回来后，ghostty 窗口顶部出现一大片空白、按 ⌘⇧R 刷新也不顶用"的问题，做对症修复。这跟之前的"字体变化错位"不是同一回事，根因在窗口可见性回调里。

**变更内容**
- 修改 `src/renderer/Thread.zig` —— 在窗口"从隐藏切回可见"（`.visible` mailbox 消息 `v == true` 分支）的处理里，在 `updateFrame()` 之前加一行 `self.renderer.markDirty()`，强制把整屏所有 cells 标记为脏。

**技术决策**
- 根因定位：ghostty 的渲染器走"dirty rectangle"优化——只重画"被标记为脏"的 cells。窗口隐藏期间画面没有任何变化，所有 cells 的 dirty 标记都是 `.false`；窗口切回可见时只调 `updateFrame()` → 走 partial rebuild 路径 → scrollback 行不被重画 → 表现为顶部空白。
- 修复方式选了"在 mailbox `.visible` 处理里强制 markDirty"——这是最对症、最小侵入的改动（1 行核心代码），让"切回窗口"这一系统事件自动触发完整重画，**用户不需要手动按刷新**。
- 没动手动刷新（⌘⇧R / 右键"刷新画面"）的 `setFontSize` 实现——因为 `setFontSize` 末尾本来就会调 `markDirty()`，所以理论上手动刷新也能修这个问题（用户之前反馈"刷新没用"实际是因为他用的 ghostty 进程是 12:39 启动的早期 1.3.3 版本，那个版本的刷新还是初版的 `render` 实现，不是真刷新）。这次只补窗口可见性回调这一处，手动刷新链路保持不动。

**端到端验证证据**
- `zig build -Doptimize=ReleaseFast` 通过
- `xcodebuild -configuration ReleaseLocal` 通过
- 覆盖 `/Applications/Ghostty Pro 中文版 1.3.3.app` 完成
- 待用户重启 1.3.3 进程后实测：(1) 切到其他 app 再切回 → 顶部不再空白；(2) 把窗口拖到一边再恢复 → 同上

**已知问题**
- 修复必须重启 ghostty 进程才生效（当前进程加载的还是旧版代码）
- 没修"⌘⇧R 手动刷新"链路 —— 因为根因不在那（setFontSize 实现是正确的，问题在窗口事件回调没触发整屏脏标记）

---

## 2026-06-22 · 加入"刷新画面"功能 + 右键菜单中文化

**任务简述**
针对用户反馈"改字体大小或拖窗口到另一块屏幕后，终端内容显示错乱"的问题，新增一个一键刷新当前画面的功能。用户可以按快捷键 `⌘+⇧+R`（Linux/Windows 为 `Ctrl+Shift+R`），或在右键菜单里点"刷新画面"。同时把右键菜单 11 项英文菜单文案全部汉化。

**变更内容**
- 修改 `src/input/Binding.zig` —— 在 `Action` 枚举中新增 `redraw` 变体，并登记到 surface scope。
- 修改 `src/Surface.zig` —— 加 `.redraw` 的处理分支，调用已有的 apprt `render` 动作触发重画（不清屏、不丢内容）。
- 修改 `src/input/command.zig` —— 在命令面板登记 `redraw` 条目（命令面板里可搜到"Refresh Display"）。
- 修改 `src/config/Config.zig` —— 默认 keybind 新增 `cmd+shift+r=redraw`（macOS）/ `ctrl+shift+r=redraw`（Linux/Windows）。
- 修改 `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`：
  - 右键菜单 11 个菜单项英文 → 中文：复制 / 粘贴 / 向右拆分 / 向左拆分 / 向下拆分 / 向上拆分 / 重置终端 / 终端检查器 / 只读模式 / 修改标签页标题… / 修改终端标题…
  - 新增"刷新画面"菜单项，位于"重置终端"上方，带 `arrow.clockwise` 图标
  - 新增 `refreshTerminal(_:)` IBAction，发送 `redraw` 动作字符串给 libghostty

**技术决策**
- 底层复用已有的 apprt `render` action（`src/apprt/action.zig:186`），不新增渲染接口，最小侵入
- 用户层暴露为新动作 `redraw`（而不是把 `render` 直接暴露给用户），保留命名层次的清晰：`redraw` = 用户意图，`render` = apprt 内部信号
- 跨平台快捷键用 `inputpkg.ctrlOrSuper(.{ .shift = true })`，自动适配 macOS（super）和 Linux/Windows（ctrl）
- 菜单文案直接硬编码中文（项目目前完全没做 i18n，Localizable.strings 文件都不存在），不为这次需求额外引入本地化框架——属于二开定制化路线
- 右键菜单"刷新画面"放在"重置终端"上方，从轻到重的顺序：刷新（仅重画）→ 重置（清屏复位）

**端到端验证证据**
- `zig fmt --check` 通过：4 个 Zig 文件语法格式正确
- `zig build` 通过：完整编译核心库无错误（Zig 0.15.2）
- 待用户在 Xcode 里 build macOS App 后实测：(1) 按 `⌘+⇧+R` 画面立刻重画；(2) 右键菜单显示中文 + 含"刷新画面"项；(3) 改字体大小 / 跨屏拖拽后按一下刷新画面，画面整齐

**已知问题**
- 这次是"治标"方案——字体变化 / 跨屏拖拽后画面错位的根因（grid 重排时机问题）没动；按刷新键是兜底，画面错位本身仍可能发生
- 本次只改了 macOS 右键菜单。Linux GTK 端的菜单文案没动（GTK 端有自己的菜单和翻译机制）
- Linux GTK 端的 `redraw` action 路由是否生效未实测（理论上能用，因为 apprt `render` 是 GTK 已实现的）

---

## 2026-06-04 · 修复窗口跨屏时内容花屏/消失

**任务简述**
窗口在不同清晰度的显示器之间拖动时（如 Retina 屏与普通屏之间），终端画面会花屏或像内容消失，需要点击/敲键才会恢复。本次针对这一渲染时序问题做修复。

**变更内容**
- 修改 `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` —— 在 `windowDidChangeScreen`（窗口跨屏事件）里，除原有的立即刷新外，新增一次延迟 0.2 秒的"兜底刷新 + 强制重绘"，确保屏幕稳定、拿到正确清晰度后重新渲染一帧。

**技术决策**
- 根因定位：跨屏瞬间 AppKit 派发的通知早于 `frame` / `backingScaleFactor` 在目标屏幕上稳定，立即刷新拿到的是旧清晰度；libghostty 检测到"清晰度/尺寸没变化"便提前跳过重建，画面停留在错误清晰度渲染状态，直到用户交互才恢复。对应官方 issue #2731（曾由 #6008 修复并入 1.1.3）与回归 issue #8844（1.2.0 起复现，至今未根治）。
- 选择"延迟兜底刷新"而非改动核心渲染/回流逻辑：纯 macOS 界面层时序改动，不触碰历史数据与重排（reflow）代码，风险最低；最坏情况是未完全修复，但不会让现状更糟。
- 否决了"照搬 #6008 的 4 行渲染器修复"：该修复的等价物（`setFontGrid` 末尾的 `markDirty()`）在当前重构后的 `src/renderer/generic.zig` 中已存在，问题已不在该处。

**已知问题**
- 该修复在当前开发环境无法编译（Zig + Metal + macOS）与跨屏实测，需重新构建 App 后由人工跨屏验证。
- 延迟时长 0.2 秒为经验值，若个别机器跨屏动画更慢仍可能偏早，后续可视实测情况调整。
- 仅针对"花屏 / 内容暂时消失（交互后可恢复）"这类渲染问题；若向上翻历史存在**永久性**内容缺失（交互也回不来），属于另一类回流数据问题，不在本次修复范围。

---
