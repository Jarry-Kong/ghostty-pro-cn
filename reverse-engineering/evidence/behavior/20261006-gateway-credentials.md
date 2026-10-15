# 网关凭据钥匙串接入

创建于 2026-10-06 · 最后更新 2026-10-06

VoiceGatewayCredentials 使用 macOS 原生 Security，固定恢复版独立 service，按完整已验证网关端点作为 account。保存只更新当前地址条目或新增，不删除凭据；令牌非空、无控制字符且最多 16 KiB。读取仅单条返回，未找到或失败不清空已有内存令牌。

设置中用户可明确“保存到钥匙串…”或“从钥匙串读取”。保存显示当前地址、替换规则、不联网告知，默认取消；没有启动时自动探测原版密钥或环境变量。钥匙串认证使用 LAContext.interactionNotAllowed，遇到需解锁／额外授权的情况报错而不自动弹出或接受权限提示。保存使用 WhenUnlockedThisDeviceOnly；实际系统行为仍需经用户允许的隔离测试验证。

改变规范化后的网关端点清空内存令牌并说明原因，避免旧令牌自动带往新地址；不删除已经保存的钥匙串条目。空白／末尾斜杠等不改变端点的编辑不触发清空。这是恢复安全边界，不宣称原包相同行为。

check-gateway-credential-query.swift 实际验证独立 service、主机和路径前缀隔离、查询不含令牌、安全地址拒绝及禁止交互的 LAContext；未调用任何 SecItem、读取或修改真实钥匙串。应用构建通过 /tmp/ghostty-gateway-credentials-build.log。

用户随后明确允许隔离测试。check-gateway-keychain.swift 使用新的 Ghostty-Recovery-Test-UUID service、example.invalid 地址和固定虚构令牌；实际通过未找到、保存、读取、更新、不同地址隔离、非法值拒绝且原值保持、删除及确认删除。随机测试条目已清理，默认恢复 service 和真实凭据未访问。为测试实际 save/read 方法增加显式 service 参数，产品调用仍用独立恢复命名空间默认值。

重启、钥匙串锁定与拒绝授权以及实际设置界面均未验收；环境导入／原版凭据迁移仍未完成。不将隔离 CLI 存取证明扩大为实际应用跨构建签名或完整凭据验收。

后续同一检查增加独立子进程读取同一随机服务，实际通过，证明不是父进程内存结果；子进程仅允许格式校验通过的 Ghostty-Recovery-Test-UUID 参数。之后更新／删除及删除确认仍通过，最终应用构建通过。机器重启和不同签名应用读取不在此检查覆盖范围。

已获许可的隔离存取重跑命令：`xcrun swiftc macos/Sources/Features/Voice/VoiceGatewayCredentials.swift reverse-engineering/check-gateway-keychain.swift -o /tmp/ghostty-check-gateway-keychain && /tmp/ghostty-check-gateway-keychain`。该命令会写入并删除随机测试 service 的虚构凭据，不是只读查询检查。

重跑只读查询构造检查：`xcrun swiftc macos/Sources/Features/Voice/VoiceGatewayCredentials.swift reverse-engineering/check-gateway-credential-query.swift -o /tmp/ghostty-check-credential-query && /tmp/ghostty-check-credential-query`。

后续普通配置保护：地址文本框即时绑定曾可将含账号／查询密钥的地址编码进 UserDefaults，即使发送时拒绝仍不足够。现共用持久化快照拒绝这些地址、片段、HTTP 和未完成地址，仅保留上次安全地址，其他设置照常保存；没有上次安全地址时不保存地址字段。输入仍留在界面内存供修正，不读或删除真实钥匙串。合成密钥 URL 的编码排除、保留安全地址、其他设置保存、无历史／旧历史不安全和明确清空检查实际通过；应用构建通过 /tmp/ghostty-gateway-safe-persistence-build.log。测试没有写真实偏好。
