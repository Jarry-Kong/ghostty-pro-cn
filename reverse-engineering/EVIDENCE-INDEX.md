# 原包证据与恢复方向纠正

> 创建于 2026-10-04 · 最后更新 2026-10-04

## 可复查的证据

| 文件 | 内容 | 限制 |
| --- | --- | --- |
| `evidence/original-sha256.txt` | 主程序、配置和主菜单指纹 | 不是整个应用包的逐文件指纹 |
| `evidence/symbols-raw.txt` | 62,965 行原始符号 | 不等同源码 |
| `evidence/symbols-demangled.txt` | 62,965 行 Swift 符号解码 | 优化可能移除方法 |
| `evidence/model-fields.json` | 43 组字段与枚举反射描述 | `type_mangled` 中二进制符号引用尚未完全解码，不应当作最终类型名 |
| `evidence/strings-utf8.txt` | 14,560 项 UTF-8 常量字符串 | 仅 `__cstring` 区，不是所有 Swift 内嵌文字；包含上游字符串 |
| `evidence/source-paths.txt` | 167 条编译时 Swift 源文件路径 | 路径不表示本机存在对应源码 |

运行 `python3 reverse-engineering/extract-evidence.py` 可重新提取反射和字符串。脚本只读原包，写入证据目录，不读取钥匙串。

## 已确认的重大差异

### 历史会话

原包字符串明确写明扫描 `~/.claude/projects`，恢复命令为 `claude --resume`。符号存在 `SessionLibraryScanner.scanAll()`、`readRecord(file:projectDir:)` 和 `SessionRenamer.rename(_:to:)`。

真实 `SessionRecord` 字段：`id`、`file`、`projectDir`、`workingDirectory`、`name`、`nameSource`、`lastActivity`、`lastPrompt`、`isRunning`、`runningPID`。编号是字符串。名字来源枚举为自定义、模型生成、未命名（`custom/ai/none`）。

筛选枚举是全部、近期、空闲（`all/recent/idle`），不是此前推测的全部、置顶。打开模式支持当前窗口标签页、新窗口标签页、分别开窗口、新窗口分列。原包还包含运行中防重复打开、复制恢复命令、名称编码损坏提示、同步 Claude 名称等线索。

因此此前“保存标题和目录，再开终端”的实现只能称为终端书签，不能认定恢复了原包历史会话。不得据此覆盖 Claude 原始记录。

本机只读检查发现 11 个顶层 JSONL 文件，仅输出记录类型和字段名，没有输出对话内容。新增扫描器保持原始文件不变，忽略子代理记录，处理损坏行和两种用户消息格式。仍待确认名称文件格式、运行状态识别和全部原包筛选规则。

### 朗读

原包支持“朗读 Claude 最新回复”，不是只有选中文本；快捷键文字线索为 `⌥⌘S`。原包历史保存的是分段音频，可拖动、重听，包含容量和条数清理规则。此前只保存文本的历史格式不能替代它。

代码模式枚举为跳过、简化、逐字（`skip/simplify/verbatim`）；语音来源为系统、网关。原包存在规则清洗、模型改写、录音告知、叠加控件和网关失败后本次回退系统语音的线索。

网络字符串线索：`/bailian/audio/tts` 和 `qwen-audio-3.0-tts-plus`；这只是原包内部网关线索，不证明可直接套用公开接口。完整请求字段、音频响应、权限和取消规则仍需核对。本轮未读取密钥、未访问网关、未发送对话。

## 待验收行为

- 原包窗口和菜单：计算机控制工具获取应用时超时，未获得界面证据。
- Claude 原始名称同步属于原数据写入：实施前需备份并明确确认。
- 真实会话恢复会启动 Claude 进程，须验证命令转义和运行中防重复，不以普通终端打开成功代替。
- 远程朗读必须先获得具体网关测试授权；不得自动使用本机发现的凭据发送私人内容。
