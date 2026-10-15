# 历史会话恢复分析

> 创建于 2026-10-03 · 最后更新 2026-10-03

当前安装包包含 `SessionRecord` 数组的 Combine 发布属性、`SessionLibraryModel.Filter` 枚举，以及 `session.json` 和 `sessions` 字符串线索。`SessionRow` 的界面符号显示它至少支持：

- 会话名称编辑；
- 会话目录的缩略显示；
- 相对时间显示；
- 选中状态；
- 行级操作按钮。

当前阶段先建立 Codable 模型和文件存储协议，具体字段以运行时数据和后续反汇编结果补齐。
