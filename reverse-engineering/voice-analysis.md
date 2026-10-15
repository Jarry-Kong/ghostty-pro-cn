# 语义朗读恢复分析

> 创建于 2026-10-03 · 最后更新 2026-10-03

安装包链接了 AVFAudio，并包含 `SpeechPlayer`、`SpeechSegment`、`VoiceHistoryEntry` 和 `VoiceTranscriptWindow`。播放器同时支持内嵌音频数据和远程 URL，具有播放、暂停、继续、停止、跳转、速率和进度回调。

目前不能仅凭符号确定远程语音服务的请求格式，因此恢复时将播放器与语音生成服务解耦：播放器先接受本地 `Data` 或 `URL`，服务协议后续根据二进制字符串和运行日志补齐。
