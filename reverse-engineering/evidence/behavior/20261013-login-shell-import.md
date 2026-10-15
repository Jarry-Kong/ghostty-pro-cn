# 登录 Shell 令牌导入

> 创建于 2026-10-13 · 最后更新 2026-10-13

功能：VOICE-05、VOICE-07、DATA-01；关联 T-022、T-038 的部分步骤。

## 原包证据

原包符号包含 `VoiceSettings.readFromLoginShell(_:)` 和 `VoiceSettings.importFromLoginShell(completion:)`。静态文案明确入口为“从终端环境导入”，读取 `ANTHROPIC_AUTH_TOKEN`，并显示正在读取、未找到及保存到系统钥匙串状态。

## 恢复实现

- 用户点击后先显示具体 HTTPS 网关端点和操作范围，默认取消；未确认不启动 Shell。
- 使用当前用户数据库登记的登录 Shell，只执行固定命令读取 `ANTHROPIC_AUTH_TOKEN`；不拼接用户输入。
- 临时输出权限为 0600，结束即删除；10 秒超时，输出最多 1 MiB，令牌最多 16 KiB，拒绝控制字符和非法 UTF-8。
- 成功后写入恢复版当前端点的独立钥匙串命名空间；不读取或覆盖原版凭据，不发网络请求。

## 验证与限制

虚构多段输出、末项选择、缺标记、空值和控制字符检查通过；`RecoveredWindowTests` 5 项同时通过，日志 `/tmp/ghostty-shell-import-20261013.log`。本轮没有点击真实导入、启动用户登录 Shell或访问钥匙串，因此真实环境导入和原包逐字布局仍未验收。
