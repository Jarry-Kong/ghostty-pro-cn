# 原包音频历史格式与只读兼容

创建于 2026-10-06 · 最后更新 2026-10-06

关联 VOICE-06、DATA-01、T-031／039。当前为已取证格式的合成兼容检查，不是完整旧数据验收。

## 原包依据

- defaultRootDirectory 位于 0x10013b5b0，读取 Bundle.main.bundleIdentifier（0x10013b6b0），NSApplicationSupportDirectory／用户域（0x10013b734—73c），追加包标识及 VoiceHistory（0x10013b8f0—918）。原包 Info.plist 的标识为 com.mitchellh.ghostty.pro-cn。
- listEntriesCore 位于 0x100140238，0x100140464—478 内嵌 meta.json；每个录音目录分别解码。
- 反射字段：id 为 String；createdAt、summary、projectName、terminalTitle、totalDuration、segments、wasRewritten。片段字段 index、text、fileName、duration。
- encoder 初始化 0x1001433ec，0x1001434d8 设置日期策略，GOT 0x100f3cae0 为 JSONEncoder.DateEncodingStrategy.iso8601；同时存在 decoder iso8601 符号。恢复版按这一格式读取。

## 实施与验证

新增 OriginalVoiceHistoryReader，和恢复版 UUID 索引分开；原目录只读，不迁移、复制或清理。列表读取 meta.json，支持字符串编号、损坏项计数、日期及片段字段；播放按原目录中的文件实际解码，无需重新合成。拒绝越界文件名、软链接、异常容量与重复片段索引。

历史窗口展示原版录音只读分组；打开窗口只读取数据，明确“刷新”才恢复本版本从回收站找回的索引。日期显示采用中文区域，不把系统英文相对时间当中文界面。

check-original-history.swift 使用专用临时目录、按原包字段建立的 meta.json 和真实系统合成 WAV；已验证非 UUID 编号、读取、元数据原字节不变和损坏项计数，退出码 0。追加越界文件名负例后的复测同样退出码 0。新增 XCTest；只读读取应用构建通过，中文日期／目录选择与测试产物补充版构建中。没有读取私人录音内容到日志或触发远程服务。

按原包规则推导的 Application Support/com.mitchellh.ghostty.pro-cn/VoiceHistory 本机当前不存在；另检查两个常用旧包标识目录也未找到。不能由此断言机器上没有任何其他版本录音，更不能宣称真实旧数据全部兼容。

增加用户明确选择旧录音根目录的只读入口，支持其他包标识或手动备份位置。选择后仅保存目录偏好并读取，不迁移、不进入恢复版清理范围；代理没有自动选择私人目录。

目录选择与新增 XCTest 的 build-for-testing 已退出码 0，日志 /tmp/ghostty-recovery-original-history-picker-build.log。测试宿主运行仍未验收，不能替代真实旧录音和界面检查。

## 未完成

真实旧录音、全部格式与部分录制规则、原版目录发现、导入／迁移授权、旧音频实际听觉和完整界面对照仍未验收。当前只读分组是兼容接入状态，不宣称最终 UI 完全复刻。
