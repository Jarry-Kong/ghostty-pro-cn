# 原包声音目录与旧编号兼容

创建于 2026-10-06 · 最后更新 2026-10-06

仅读取原包静态数组，未读取用户偏好、密钥或发送请求。

gatewayVoices outlined 数组位于 0x101010d48，元素数 4，数据起于 0x101010d70，每项 id／name／trait 三个 Swift 字符串，合计 48 字节：

| 编号 | 中文名 | 特征 |
| --- | --- | --- |
| longanlufeng | 龙安鲁风 | 明亮开朗 |
| longanlingxin | 龙安灵心 | 知心温暖 |
| longanlingxi | 龙安灵希 | 可爱甜美 |
| longanhuan_v3.6 | 龙安欢 | 自然平实 |

obsoleteVoices 初始化函数 0x1001551d4 使用位于 0x1010102f8 的十项数组构造集合；声音 getter 0x10015542c 调用 contains，命中时回退 longanlufeng。十项为 Cherry、Serena、Ethan、Chelsie、longxiaochun、longxiaochun_v2、longwan、longcheng、longhua、longxiaoxia。不把这些旧编号展示为仍然可用的网关声音。

恢复设置模型新增可选存储字段 gatewayVoice，旧恢复配置缺字段时不影响其他设置。getter 采用原包旧编号回退，未知自定义编号原样保留；编码时不持久化任何令牌。远程模式下显示四项原生 Picker 与“其他（手填参数名）”输入，不增加第三方控件。设置的完整原包布局、实际网关声音和真实桌面选择仍待验收；当前控制器远程入口仍未接通，选择远程不代表可以合成。

check-voice-settings.swift 实际验证缺字段默认、十项旧编号、目录顺序、自定义编号编码往返及既有启用开关兼容，退出码 0；应用构建通过 /tmp/ghostty-voice-catalog-build.log。

重跑静态数据：`xxd -s 0x1010d48 -l 256` 与 `xxd -s 0x10102f8 -l 208`，传入原包 Contents/MacOS/ghostty。__DATA 文件地址映射沿用网关协议证据，不扫描个人数据。
