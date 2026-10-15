# 系统语音真实内存音频恢复

创建于 2026-10-06 · 最后更新 2026-10-06

关联 VOICE-04／06、T-028—033。当前是合成基础层，不是播放与历史完整验收。

## 原包与平台依据

原包存在 SystemSpeechSynthesizer、分段播放器和 VoiceHistoryEntry.SegmentRecord（index、text、fileName、duration）等符号／反射字段。真实时长与分段文件是必要要求，不能以文字长度推测。

本机 Xcode SDK 的 AVSpeechSynthesis.h 第 240 行声明 writeUtterance:toBufferCallback:，macOS 10.15 起可用。恢复版使用该接口生成实际 PCM 缓冲区，以原生 AVAudioConverter 转换为交错 16 位 PCM，再生成内存 WAV；默认不写音频文件。

## 已实现与验证

- 新增 SystemSpeechRenderer：逐缓冲区同步消费，避免异步任务持有后可能被复用的缓冲区；请求独立加锁，完成／取消只恢复一次异步结果。
- 时长来自真实帧数除以采样率；音频格式变化、空音频及异常数据明确失败；单片段 64 MiB 内存保护不视为已证明原包默认上限。
- 请求取消后不会返回成功音频；完成或取消均停止当前原生合成，不让过期回调写入新请求。
- 最初使用专用临时 CAF 验证帧数、时长和权限，完成后清理；最终实现改为内存 WAV，避免“不保存历史”时仍落音频盘。
- check-system-speech.swift 实际调用系统合成，只使用固定无私人内容的中文短句。AVAudioPlayer 成功解码内存 WAV，正时长与合成帧数计算结果差小于 0.001 秒；预先取消请求抛出 CancellationError。运行退出码 0，未播放声音、未调用远程语音、未写音频文件。
- 新增 XCTest 对应检查，build-for-testing 退出码 0，日志 /tmp/ghostty-recovery-system-audio-build.log；不是宿主测试已通过。

## 待完成

尚未接入 VoiceController 的实际播放路径。现有朗读仍走直接系统朗读；真实分段播放、暂停／拖动／倍速、片段时间映射、持久历史、首次录音告知、离线重播、限额清理与原版数据兼容尚待实现。不能标 VOICE-04／06 完成，也不声称已验收实际可听声音。
