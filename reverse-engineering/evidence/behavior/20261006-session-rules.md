# 会话名称、筛选、分组与数量限制的二进制依据

> 创建于 2026-10-06 · 最后更新 2026-10-08

关联：SESSION-01—03、SESSION-05、UI-02、UI-04；这份记录是 E2 二进制证据，不代替原包受控样例与真实恢复验收。

基准仍为指定 1.6.0 修复版，指纹与 [原包菜单记录](20261006-original-ui.md) 相同。反汇编使用 Xcode 的 llvm-objdump，结合 `otool -Iv` 导入表和 swift-demangle 解析调用名，不把反汇编器显示的最近符号名当真实调用。

## 已确认规则

- 原包 readRecord（`0x100075c20`）包含 `customTitle`、`aiTitle`、`lastPrompt` 字段线索；名称和问题预览是不同字段。`0x1000762ec` 是 customTitle 字典查询。
- `0x100076dd0—0x100076dd8` 从文件 URL 删除扩展名、取最后路径分量，得到会话编号。恢复版加入 UUID 文件名与记录编号一致性保护，防止混入别的会话行改变恢复目标。
- `0x100076e18—0x100076e54` 在文件内自定义名称为空时调用 `readSidecarTitle(projectDir:sessionID:)`；该辅助函数入口 `0x100079444`。先把编号作为目录追加到项目目录，再追加 17 字节的 `custom-title.json`，读取 JSON 的 `customTitle`；非空才返回。恢复版按此只读回退，损坏文件不回写。
- 侧文件路径为 `项目目录/会话编号/custom-title.json`。恢复版另外限制文件大小及软链接不能逃出项目目录，属于安全保护；不据此声称所有旧格式均兼容。
- 原包 visible（`0x100089874`）以 now 加 `-604800.0` 秒作为近期边界。`0x100089bb8` 调用 Foundation.Date 的 `<` 运算，结果为真则跳过，所以恰等于边界的记录仍被保留。恢复版测试覆盖等于边界。
- 原包 groupTitle（`0x10008eac8`）含“今天”“昨天”“最近 7 天”“本月更早”“更早”；通过 DateComponents.day 的日龄判断，比较阈值 6、29。最近 7 天筛选是秒区间，分组是日龄区间，不能混用。
- 原包 overLimit（`0x10008b4b0`）先比较模式编号 3（分列），在 `0x10008b594` 比较选择数 5，再由 `cset hi` 返回超限：因此分列最多 5 个，不是临时实现的 4 个。具体像素比例和焦点还需真布局验收。

## 可复查文件

`../disassembly/session-record.txt`、`session-visible.txt`、`session-group-title.txt`、`session-limit.txt` 是原始诊断输出；同目录的 `session-scanner-annotated.txt`、`session-visible-annotated.txt`、`session-group-title-annotated.txt`、`session-limit-annotated.txt` 和 `session-sidecar-annotated.txt` 补充了解码的导入调用。

复现示例：

```sh
xcrun llvm-objdump --disassemble --start-address=0x100075c20 --stop-address=0x100077434 \
  'Ghostty Pro 中文版 1.6.0 修复版.app/Contents/MacOS/ghostty'
otool -Iv 'Ghostty Pro 中文版 1.6.0 修复版.app/Contents/MacOS/ghostty'
```

## 尚未证明或未实施

- 完整写入／改名同步协议、编码损坏提示和原始记录写入仍未实施；没有用猜测的写入覆盖原数据。
- 原包首装默认模式尚未确认。恢复版目前保存自身的模式选择，不从原版读取或迁移设置；此项不能声称已对照一致。
- 运行状态当前实现支持本用户的已识别 Claude 原生程序／官方 Node 程序的 UUID 参数定位；无编号或权限不足时保留不确定状态。其他包装方式、所有无参数新会话及跨进程真实切换尚未验收。
- 已加入本应用进程归属与 PID 观察，避免窗口还在时错误认为会话仍运行或把外部进程误切到缓存窗口。首次启动始终未观察到进程的失败情形仍需要关闭启动窗口后重试，不宣称此边界已与原包一致。

## 2026-10-08 跨进程检查

- 新增 `check-session-process.swift`，把测试程序自身临时编译为名为 `claude` 的独立子进程，只使用随机 UUID 和临时工作目录。
- 实际验证精确会话编号映射到子进程 PID、同目录活跃、进程归属、退出后清除；无编号进程会把该目录标为状态不确定并在退出后解除。
- `check-recovered-logic.sh` 已纳入该检查，七组集中检查退出码 0；临时进程全部退出，临时目录已清理。
- 这覆盖 T-020／021 的进程扫描子步骤，不代表应用窗口切换、外部终端提示或真实 Claude 会话已经验收。

## 原版问题提案：OPT-001（未批准）

“本月更早”是日龄 7—29 天的标签，并非严格自然月，跨月时可能让人误解。本轮保持原标签与规则。若用户希望优化，可改为“近 30 天内较早”；只改文案，不改变筛选。当前没有批准，也没有实施该优化。
