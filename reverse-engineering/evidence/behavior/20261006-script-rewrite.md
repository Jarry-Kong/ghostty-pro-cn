# 模型改写协议与提示词取证

创建于 2026-10-06 · 最后更新 2026-10-06

只分析原包，不读取账户／环境密钥或发送请求。

## 已确认

ScriptRewriter.rewrite 位于 0x100117dc4。0x10011817c—188 设置 POST；0x1001181a4—1c8 写 Content-Type；0x1001181d0—234 组 Bearer 与 Authorization；0x100118248—268 写 anthropic-version 2023-06-01；0x10011826c—270 将最终超时设为 20 秒。路由相关规范化函数位于 0x100118818，出现 /v1/messages 与 /v1，具体拼接规则仍待完整恢复。

0x1001182a0—31c 构建 model、max_tokens=8000、system；0x100118320—484 构建 messages，单条 role=user，content 为地址 0x100942ff0 的固定前缀“请把下面这段回复改写成口播稿：”加两个换行和原文。顶层共四项，不擅自加 temperature、stream 或其他参数。

系统提示词构造 0x10011aeec：先地址 0x1009430d0 的共用前言，再强度说明（保守 0x100943730／自然 0x100943020），最后 0x100943260 的规则与输出要求。各原始字符串字节数 390、192／174、1217；完整保守 1799 字节，自然 1781 字节。

- 保守 SHA-256：020b961237d25dcb96d71cf106c583dcea13bcd0170257d78e829bcda71735f1
- 自然 SHA-256：41f9cf28d8ba414303bfb032aa46093a70c977754da8cc58f22456f219431041

恢复源码 systemPrompt 与两个原包拼接结果 SHA-256 完全一致，检查实际通过；这证明提示词字节一致，不证明模型必然遵守“不改事实”等要求。

响应 extractText 位于 0x10011b218，顶层 content 数组，筛选 type=text 的 text 字符串，0x10011b71c—728 用换行拼接，0x10011b744—760 trim 首尾空白／换行，空结果为 nil；非 200 的回调不提供改写。已实现本地提取，思考／工具块排除、多段、空白、损坏和错误状态检查通过。恢复解析另限制 JSON 4 MiB，是安全边界，不假称原包同样限制。

## 当前范围

触发范围后续取证：isWorthRewriting 位于 0x100117cd4，0x100117cf4 直接计算传入字符串 Swift count；0x100117d4c—84 将非正最小字数回退为 120；0x100117d54—58 为达到最小字数（含等号）；0x100117d8c—94 拒绝 >=8001。因此范围为有效最小字数至 8000（含）。已实现纯判断，119／120、8000／8001、自定义阈值、非正回退和多码位表情计数实际检查通过；控制器开关与具体输入仍未接入，不能据纯函数宣称自动改写已启用。

模型／缺省配置后续取证：rewriteModels 数组位于 0x101010c90，三项 id／name／note。依次 claude-haiku-4-5／Haiku 4.5／最快最省，推荐；claude-sonnet-5／Sonnet 5／质量更好，慢一些；claude-opus-5／Opus 5／最好，但慢且贵。缺模型 getter 0x100155870—894 使用 0x100944ad0 的 claude-haiku-4-5。备注仅为原包静态文案，不是对当前实际模型可用性或费用的保证。

VoiceSettingsModel.init 的 0x10015b3e4—440 用 voice.rewriteMinLength 取整数，非正数回退 120。VoiceSettings 初始化字典 0x100154da0—dc4 对 voice.rewriteEnabled 写 false，随后通过 registerDefaults 注册。因此恢复可选配置缺字段时改写关闭、最小字数 120；不提前开启发送。

模型选择器与自定义编号已接入现有设置，并明确“尚未启用发送”；原包备注保留、最小字数目前只展示，触发条件和阈值控件未接入。缺字段、非正数回退、有效阈值／模型／开关编码往返实际检查通过；选择器构建通过 /tmp/ghostty-rewrite-models-build.log，后续纯开关字段亦独立编译检查通过。完整布局／默认强度／控制器触发范围仍待核对。

后续地址／客户端接入：messagesURL 原包实际入口为 0x10011880c，先调用共用 normalizeBaseURL；0x100118888 检测完整 /v1/messages 并原样解析，0x100118920 检测 /v1，命中后 dropLast(3) 并再次规范化，最后 0x1001189cc 追加 /v1/messages。已实现根／v1／完整消息地址／多斜杠／路径前缀与非法地址检查，语音基础地址回归同次通过。

ScriptRewriter 独立客户端已复用 QwenTTSClient 的临时会话、取消、默认禁止重定向及限额流读取，响应限制 4 MiB，不新增第二套传输框架。URLProtocol 完全离线验证请求头、成功 text 输出、500 返回 nil、取消前置保护；既有语音客户端两条音频、令牌隔离、取消与限额回归也通过。应用构建通过 /tmp/ghostty-script-rewrite-client-build.log。

本轮没有接入设置或朗读控制器，没有真实模型调用。下文“尚未实现改写客户端”为上一批次状态；长度阈值／默认值、模型目录、独立网关／凭据／许可、控制器失败保留规则清洗稿与真实事实保留验收仍未完成。

客户端重跑：`xcrun swiftc macos/Sources/Features/Voice/SpeechPlayer.swift macos/Sources/Features/Voice/QwenTTSRequest.swift macos/Sources/Features/Voice/QwenTTSResponse.swift macos/Sources/Features/Voice/QwenTTSClient.swift macos/Sources/Features/Voice/ScriptRewriteRequest.swift macos/Sources/Features/Voice/ScriptRewriteResponse.swift macos/Sources/Features/Voice/ScriptRewriter.swift reverse-engineering/check-script-rewrite-client.swift -o /tmp/ghostty-check-rewrite-client && /tmp/ghostty-check-rewrite-client`。

ScriptRewriteRequest／ScriptRewriteResponse 已实现并通过离线检查，重用网关授权请求的验证与头构造；已有语音请求回归同次通过，应用构建通过 /tmp/ghostty-script-rewrite-build.log。尚未实现改写客户端、长度阈值／默认值、模型目录／独立网关、用户发送许可、控制器及失败回到规则清洗稿，因此 VOICE-08 不算完成。

重跑：`xcrun swiftc macos/Sources/Features/Voice/QwenTTSRequest.swift macos/Sources/Features/Voice/ScriptRewriteRequest.swift macos/Sources/Features/Voice/ScriptRewriteResponse.swift reverse-engineering/check-script-rewrite.swift -o /tmp/ghostty-check-script-rewrite && /tmp/ghostty-check-script-rewrite`。
