# 网关客户端离线验证

创建于 2026-10-06 · 最后更新 2026-10-06

## 实现边界

QwenTTSClient 复用已经取证的请求构造、响应提取和播放层音频准备。客户端使用临时 URLSession，禁用缓存、Cookie、共享凭据与额外默认请求头，结束或错误时取消并销毁会话。响应按字节读取，声明长度或实际内容超过 64 MiB 拒绝；检查任务取消。

音频 URL 只允许网关主机或调用者显式允许的其他主机；音频 GET 独立构造，不带 Authorization 或 Cookie。当前禁止全部自动重定向：尚未取得额外地址授权，不把服务重定向当作授权。它与原包的重定向行为尚未对照，合法重定向服务当前可能失败；不能标为完整网关验收通过。

调用者仍必须取得具体目的地址、文字及凭据发送许可。未接入 VoiceController／设置／钥匙串，代理没有读取密钥或调用真实服务。没有自动回退实现；本记录不代表用户应用中的远程选项已经可用。

## 实际离线检查

通过 URLProtocol 拦截所有请求，所有域名为 example.invalid／other.invalid，凭据固定 synthetic，使用内存构造的 0.25 秒静音 WAV，未访问网络、发声或保存文件。

- Base64 响应 → 真实音频字节 → 原生准备验证，字节与时长一致。
- URL 响应 → 显式允许主机的 GET → 音频准备验证，GET 不含令牌／Cookie。
- 未允许的音频主机拒绝，401 保留鉴权错误。
- 任务开始前取消及已进入 URLProtocol 的等待响应任务取消，均不能返回音频。
- Content-Length 为 67108865 的响应在读取前拒绝；未构造巨大响应。实际无长度超限流、超时和重定向尚未实测。

运行命令：

```sh
xcrun swiftc macos/Sources/Features/Voice/SpeechPlayer.swift macos/Sources/Features/Voice/QwenTTSRequest.swift macos/Sources/Features/Voice/QwenTTSResponse.swift macos/Sources/Features/Voice/QwenTTSClient.swift reverse-engineering/check-qwen-client.swift -o /tmp/ghostty-check-qwen-client && /tmp/ghostty-check-qwen-client
```

实际退出码 0，应用构建通过（/tmp/ghostty-qwen-client-build.log）。MP3／PCM、真实网关、服务回退、隐私确认窗口、设置持久化及整体验收仍未完成。
