# 功能恢复地图

> 创建于 2026-10-03 · 最后更新 2026-10-03

| 功能 | 安装包证据 | 当前仓库状态 | 恢复策略 |
| --- | --- | --- | --- |
| 中文版名称 | `CFBundleDisplayName` 为 `Ghostty Pro 中文版` | 已存在 | 保留现有配置 |
| 标题修改 | `TabTitleEditor`、`changeTitleMenuItem` | 已有完整实现 | 直接复用并补测试 |
| 历史会话 | `SessionLibraryWindow`、`SessionLibraryModel`、`SessionRecord`、`SessionRow`、`session.json` | 模型、JSON 存储、窗口和菜单入口已建立 | 继续接入真实终端恢复动作 |
| 语义朗读 | `VoiceSettings`、`SpeechPlayer`、`SpeechSegment` | 设置模型和播放器基础实现已建立 | 继续确认远程服务和状态通知 |
| 朗读历史 | `VoiceHistoryEntry`、`VoiceTranscriptWindow`、`HistoryRow` | 数据模型、JSON 存储、窗口和菜单入口已建立 | 接入真实朗读流程 |

## 已确认的关键接口线索

`SpeechPlayer` 暴露了 `play(data:)`、`play(remote:)`、`pause()`、`resume()`、`togglePause()`、`seek(to:)`、`stop(notify:)`，并包含播放进度、时长、速率和远程回退 URL。

`AppDelegate` 暴露了 `showSessionLibrary`、`showVoiceSettings`、`showVoiceTranscript`，说明这些功能通过应用级菜单或通知进入。

`SessionRow` 暴露了标题编辑、名称徽标、目录缩略显示、相对时间和复选框等界面组成。
