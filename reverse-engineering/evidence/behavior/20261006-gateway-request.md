# 原包网关语音请求取证

创建于 2026-10-06 · 最后更新 2026-10-06

只分析原包 Mach-O，未读取偏好中的密钥、钥匙串或发送请求。对应原包哈希沿用基准记录。

## 已确认

后续基础地址取证：normalizeBaseURL 位于 0x100128868，其 0x1001288d8 取 CharacterSet.whitespaces、0x1001288f4 trim，0x100128914—98c 循环检测／移除末尾 `/`，函数到约 0x1001289cc 结束，后面的代码属于错误文案，不是额外 URL 改写。synthesize 0x1001291f4 调用它后追加固定路由。已接入 endpoint(baseURL:)：保留原有路径前缀，不擅自去掉 /v1 或其他前缀；基础地址应填写网关根／前缀而不是完整语音路由。

根地址、空格／多个斜杠、路径前缀实际检查通过，空地址／HTTP／查询凭据／URL 账号／换行拒绝。这些安全拒绝不是原包等价证明；原包只 trim whitespaces，不把换行当作可接受空白。VoiceSettings.voiceName getter 0x1001553e0—408 缺失配置分支的小字符串为 longanlufeng；旧声音集合映射尚未还原。

- QwenTTSClient.synthesize 位于 0x100128dd8；0x100129208—22c 引用地址 0x100943de0 的 `/bailian/audio/tts` 并拼入 URL。基础地址处理另调用 0x100128868，尚未完整还原。
- 0x100129718—72c 写入顶层键 model；0x1001297c0—7d8 默认值指向 0x100943e00 的 `qwen-audio-3.0-tts-plus`。配置值读取 voice.model，默认仅在该路径条件下使用。
- 0x1001297e0—7fc 写入顶层键 input；0x100129818—8cc 构建其五项：text 为传入文字，voice 来自 VoiceSettings.voiceName，format 为 mp3，sample_rate 为整数 24000，rate 为浮点 1.0。
- 0x100129900 分配五项输入字典，0x100129940 分配两项顶层字典；0x10012999c 调用 JSON 序列化，0x1001299f0 调用 URLRequest.httpBody setter。不是把所有输入字段放在顶层。
- 后续跟踪确认：0x1001293ac—3bc 设置 POST；0x1001293c0—3f4 设置 Content-Type 为地址 0x100942de0 的 application/json。0x1001293f8—41c 构造 `Bearer ` 并追加配置值，0x10012942c—454 写入 Authorization。
- 0x100129390—3a8 初始化请求时传入 60 秒，随后被覆盖。0x100129464 读取 Swift String.count；0x100129484—4b4 计算 `min(180, 30 + 字符数 * 8 / 100)`，0x100129554 为零长度分支 30，0x100129564 写入最终 timeoutInterval。不是固定 60 秒或按 UTF-8 字节计算。
- 原包计数使用前面 trim 的字符串（0x100129008 调用 trimming，结果 x20 存于 0x100129068 的栈偏移 0x20，与 0x100129460 的载入对应）。恢复请求默认按 trim 后 Swift 字符数计算；保留显式覆盖参数用于测试。
- 响应解析 0x10012a578 先调用 findAudioURL，0x10012a5b0 分支到 0x10012a7c0；另一分支 0x10012a5f8 调用 findBase64Audio 对应的递归 walk。尚未完整还原候选路径及非空判定，不能据此写通用“随便找到一个 URL”解析器。

## 未确认

后续已确认 HTTP 错误细分：403 无条件进入 0x10012a030，0x10012a048—68 构造 routeNotAllowed 载荷，Swift 字符串表示的地址加 32 后对应 /bailian/audio/tts；401 进入 0x10012a0e8—110 构造无关联值 unauthorized。不是检查响应体里是否有某个错误代码才分类。恢复版已对应分为路由权限和令牌鉴权错误，中文解释不回显响应体；文案仍不是已证明逐字复刻。

后续 HTTP 状态证据：0x10012a088 比较 403，0x10012a090 比较 401，0x10012a098 比较 200，非 200 到 0x10012a19c 错误路径。新增带 statusCode 的 decode 重载先拒绝非 200，再提取载荷；200、201／204／301／401／403／429／500 合成检查实际通过，错误体含有效 URL 也不进入成功解析。当前统一 HTTP 状态错误，不回显可能包含用户文本或凭据的响应体；原包 401／403 的细分条件和文案仍待恢复，不能视作错误流程完全一致。

全部请求头、基础地址规范化、递归 URL／Base64 回退条件、二次下载鉴权、错误处理及重试／回退。真实服务验收仍需目的地址、测试文本和凭据的具体授权。

## 优先音频地址路径

后续取证确认静态 urlPaths 初始化 0x10012b1a0 按顺序写入八项，outlined 数组位于 0x10100ea48—0x10100ec98。__DATA 的 vmaddr 为 0x100f84000、fileoff 为 0xf84000，因此这批数据可按地址减 0x100000000 读取。小字符串和数组元素数量直接可见：

1. output.audio.url
2. output.audio_url
3. output.url
4. data.audio.url
5. data.url
6. audio.url
7. url
8. result.audio_url

findAudioURL 的 0x10012af8c 调用 dig 逐项提取字符串并解析 URL；优先路径未命中才到 0x10012b088 的递归 walk。0x10012b150 调用 secureAudioURL；其 0x10012b3a0—4a0 检测 http、替换为 https 再构造 URL。递归候选条件与 Base64 仍未完整还原。

QwenTTSResponse.preferredAudioURL 已接入上述固定路径，仅作为完整解析器的一部分，不替代递归／Base64。拒绝文件 URL、含账号和片段等是恢复安全边界；签名查询保留，未发起二次下载。八路径、优先顺序、非法候选跳过、HTTPS、查询及不猜未知路径的离线检查通过。

## 离线实现

音频链路重跑：`xcrun swiftc macos/Sources/Features/Voice/SystemSpeechRenderer.swift macos/Sources/Features/Voice/SpeechPlaybackTimeline.swift macos/Sources/Features/Voice/SpeechPlayer.swift macos/Sources/Features/Voice/SegmentedSpeechPlayer.swift macos/Sources/Features/Voice/QwenTTSResponse.swift reverse-engineering/check-segmented-playback.swift -o /tmp/ghostty-check-gateway-audio && /tmp/ghostty-check-gateway-audio`。应用构建通过，日志 /tmp/ghostty-gateway-audio-build.log。

音频有效性后续检查：SpeechPlayer.validatedDuration 与实际 play 共用原生解码准备，验证有限正时长且 prepareToPlay 返回成功，数据最多 64 MiB。合成 WAV 经过 Base64 响应提取后字节相同、原生时长相同；空字节／非音频拒绝，所有实际播放测试 startPaused，未发声。编译运行 check-segmented-playback.swift（附带 QwenTTSResponse.swift 等既有播放源）实际通过。此检查覆盖 WAV／准备播放，不证明任意压缩音频完整可播放或 MP3／裸 PCM 支持，不替代听觉验收。

后续递归提取已实现 QwenTTSResponse.decode：八项优先路径 → 递归符合条件的 URL → 递归 Base64 候选 → Foundation 严格解码（原包 0x10012a610 options 为 0）。walk 0x10012bbf8／12bc00 使用点连接字典键，0x10012be10—54 使用 `[编号]` 连接数组路径；原包未见此函数排序字典，恢复版同样沿用字典枚举，不承诺多个同级候选跨运行排序一致。

离线实测嵌套数组路径、Base64 字节往返、URL 优先于 Base64、首段通过但全文损坏报错、非音频链接拒绝及 70 层输入拒绝。安全限制为响应 JSON 最多 64 MiB、递归深度 64、每次遍历最多 100000 节点；这些是恢复版边界，不是已证明的原包额度。返回字节仍须真实音频解码验证，返回 URL 仍须二次下载权限／重定向策略；均未接通。

后续 Base64 筛选取证：0x10012c394 比较 0x201，低于 513 返回；0x10012c3a0 将路径转小写，0x10012c3b0—434 检查 audio 或 data，另一分支 0x10012c694—6d8 检查 content。0x10012c448—458 取前 64 字符，0x10012c564—658 允许 isLetter、isNumber、+、/、=，非完整内容解码检查。已接入 isBase64Candidate 并实测 512／513 边界、路径大小写、首段非法字符以及首段通过但全文不可解码的区别。

递归 URL 筛选已定位字符串以 http 开头；小写地址包含 .mp3／.wav／.m4a／.pcm 或路径包含 audio 时尝试解析（0x10012b830—97c、0x10012bab0—aec）。完整遍历顺序、二次下载与解码仍未接入，候选筛选不是完整远程响应功能。

QwenTTSRequest 只接收已经解析好的目的 URL 和显式凭据／超时，构造请求而不发送。不读取钥匙串或偏好；尚未挂接 VoiceController，不能称为远程合成功能已接通。安全边界拒绝非 HTTPS、URL 内用户名／密码／查询／片段、空凭据、凭据控制字符及无效超时；这是恢复过程的安全限制，不据此声称原包同样拒绝这些输入。

运行：`xcrun swiftc macos/Sources/Features/Voice/QwenTTSRequest.swift reverse-engineering/check-qwen-request.swift -o /tmp/ghostty-check-qwen-request && /tmp/ghostty-check-qwen-request`。固定测试凭据和 example.invalid，检查 POST／头／两层全部字段和六种非法边界；程序没有任何网络调用。

## 重跑方法

使用 `xcrun llvm-objdump -d --start-address=0x100129630 --stop-address=0x100129978` 并传入原包 `Contents/MacOS/ghostty`；字符串使用 `xxd -s 0x943de0 -l 80`。不要带 `--macho`：本机该模式忽略地址范围，会输出整段程序。外部调用需配合 `otool -Iv` 映射，不使用误标为 `_writev` 的自动符号注释作结论。
