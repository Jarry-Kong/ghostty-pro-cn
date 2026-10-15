# 压缩音频历史与最新版设置桌面验证

创建于 2026-10-06 · 最后更新 2026-10-06

## 压缩音频实际检查

check-compressed-history.swift 在随机 Ghostty-Compressed-Test-UUID 临时目录中，以原生 AVAudioFile 将 6000 帧、24 kHz 静音 PCM 编码为 AAC／M4A；另外构造十个零系数 MPEG-1 Layer III 帧，是否有效由系统音频解码准备判断。不使用外部录音、网络、第三方编码器或发声。

M4A 和 MP3 均实际通过原生解码准备、有限正时长、正确扩展名、真实音频保存／重载、字节一致、时长一致及读取帧数大于零；M4A 的 wasRewritten 标记经索引重载保留。不是只检查文件头。未证明所有 VBR、截断音频或任意网关编码都兼容；可听效果仍待验收。

检查成功后显式删除自己创建的随机临时目录，并确认不存在才输出通过；没有操作真实录音或钥匙串。最终退出码 0。

重跑：

```sh
xcrun swiftc macos/Sources/Features/Voice/SystemSpeechRenderer.swift macos/Sources/Features/Voice/SpeechPlayer.swift macos/Sources/Features/Voice/SpeechPlaybackTimeline.swift macos/Sources/Features/Voice/SegmentedSpeechPlayer.swift macos/Sources/Features/Voice/SpeechSegment.swift macos/Sources/Features/Voice/VoiceHistoryEntry.swift macos/Sources/Features/Voice/VoiceHistoryStore.swift macos/Sources/Features/Voice/VoiceHistoryRetention.swift macos/Sources/Features/Voice/VoiceAudioHistoryStore.swift reverse-engineering/check-compressed-history.swift -o /tmp/ghostty-check-compressed-history && /tmp/ghostty-check-compressed-history
```

## 最新版实际设置窗口

确认恢复版测试终端位于空闲 shell 提示符后正常退出；应用列表确认 com.mitchellh.ghostty.debug 已停止，再启动最新 Debug 产物。没有确认 Claude 的目录信任，没有关闭原包或其他应用。

实际打开编辑 → 朗读 → 语音朗读设置：朗读开启、改写关闭、力度保守、最小字数 120、共享网关、Haiku 4.5。设置截图确认字段不重叠；向下滚动可达播放与历史，50／300 和保存录音关闭可见，没有被新增改写区域永久遮挡。

临时开启独立改写网关，实际出现地址、SecureField、空令牌时禁用的保存按钮及读取按钮；未输入令牌，未点击读取／保存／发送。随后恢复独立网关关闭、改写仍关闭，关闭设置回到测试终端。

这里证明最新恢复版控件实际存在及可滚动，不证明原包像素一致、全部编辑行为或发送确认通过；没有抓包测量所有应用流量，操作中未调用语音／模型请求。原包完整设置对照与真实声音流程仍待完成。
