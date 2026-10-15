# 系统音色回退接入

创建于 2026-10-06 · 最后更新 2026-10-06

## 原包依据

静态中文字符串和 VoiceController.fallbackNotice／fallbackReason 符号证明：语音模型不可用时本次使用系统音色，不改变设置，下次继续尝试网关；权限与后端错误有独立 didWarnPermission／didWarnBackend 提示，之后原因显示在控件。完整分段失败／重试边界与实际原版桌面流程尚未确认。

## 恢复行为

VoiceController 缺令牌／无效基础地址时不发送请求，使用系统合成；已确认发送的远程片段失败时，检查取消及当前任务代际后改用本地系统合成。下一次朗读仍读取远程设置；没有写回 settings.engine。用户取消发送确认不会触发本地播放。

CancellationError／URLError.cancelled 明确禁止回退；401／403／未授权音频地址归权限原因，其他 HTTP／超时／无可用音频归后端原因。两类提示各使用恢复版独立偏好键记一次，朗读历史控件显示“本次含系统音色”及简短原因，不回显响应体。混合远程／系统片段也不假称全部是系统音色。当前每段失败仅回退该段，后续段仍尝试网关；此批次重试范围尚未与原包实测对齐。

## 证据范围

check-speech-fallback.swift 实际通过取消拒绝、权限／后端分组、下载地址未授权及音频损坏分类；不写偏好、不生成或播放音频。控制器及界面构建通过 /tmp/ghostty-speech-fallback-build.log；之后仅追加纯分类边界检查，通过独立 Swift 编译运行，未重复整体构建。

回退提示一次性持久化、真实控制器失败到本地合成、桌面停止与声音、真实服务恢复后再次尝试仍未实际验收，不把纯分类测试当作完整回退流程通过。

重跑：`xcrun swiftc macos/Sources/Features/Voice/QwenTTSResponse.swift macos/Sources/Features/Voice/SpeechFallbackPolicy.swift reverse-engineering/check-speech-fallback.swift -o /tmp/ghostty-check-speech-fallback && /tmp/ghostty-check-speech-fallback`。
