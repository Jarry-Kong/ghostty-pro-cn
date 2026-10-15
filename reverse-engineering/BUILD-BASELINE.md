# 恢复构建基线

> 创建于 2026-10-04 · 最后更新 2026-10-13

## 备份和保护范围

源码快照：`/Users/konglingjia/Library/Application Support/Ghostty-Recovery/backups/source-20261004-baseline.tar.gz`。

SHA-256：`c3900721e4878e80a48b3b15f9278697970a1ffb96c7ef23e92c492ef490fe0c`。

这是本轮开始时的源码快照，包含之前已做的恢复改动，并非丢失前的原始源码。排除可再生成的缓存、构建产物、原包及仓库压缩包。原包保留原位，关键资源指纹见 `evidence/original-sha256.txt`。快照目录列表已检查；尚未进行完整还原演练。

2026-10-13 当前恢复源码另存为 `/Users/konglingjia/Library/Application Support/Ghostty-Recovery/backups/source-20261013-recovery.tar.gz`，SHA-256 为 `f619aada50cd0c1218b9c5d4cf9b9ba81ba05133c37c160e19b80a772166b164`。它排除 `.zig-cache`、`macos/build`、生成的 `GhosttyKit.xcframework`、原包、旧仓库 ZIP 和性能采样文件，包含项目内 Sparkle 源码。

该快照已解包到专用 `/tmp` 目录，从副本运行 `build-release.sh`，完成底层框架重建、ReleaseLocal 应用构建、深度签名校验和 3 秒真实启动；产物为 arm64。还原临时目录随后已清理，日志保存在 `/tmp/ghostty-restored-release-build-20261013.log` 和 `/tmp/ghostty-restored-release-launch-20261013.log`。后续源码变化需要刷新快照及指纹，不能把本次指纹当最终交付指纹。

## 工具链

- 完整 Zig 0.15.2 安装目录：`/Users/konglingjia/Library/Application Support/Ghostty-Recovery/toolchains/zig-aarch64-macos-0.15.2`，包含标准库。
- 执行 `bash reverse-engineering/build-core.sh` 生成本机 arm64 框架；2026-10-04 再次执行成功。
- 通过 `GHOSTTY_RECOVERY_ZIG` 可指定其他完整安装的 Zig 路径。
- 底层 Zig 使用 Command Line Tools 的 SDK，Metal 和框架封装使用完整 Xcode，避免当前完整 Xcode SDK 缺少所需 arm64 链接声明的问题。
- 本地 Sparkle 引用：`/Users/konglingjia/Desktop/Vibe coding/Sparkle-2.9.0`。该引用尚不可移植。
- 不依赖之前仅复制到 `/opt/homebrew/bin/zig` 的不完整安装；本轮没有覆盖全局可执行文件。
- `build-core.sh` 支持 `GHOSTTY_RECOVERY_OPTIMIZE=Debug|ReleaseSafe|ReleaseFast|ReleaseSmall`；非法值立即失败。默认仍为 Debug，正式交付脚本固定使用 ReleaseFast。

## 应用和测试

项目规定通过 `macos/build.nu` 构建。本机未安装 Nushell，当前使用相同的 Xcode 构建入口作为替代，不宣称已经运行该脚本。

```sh
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  "SYMROOT=$PWD/macos/build" build -quiet

xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  "SYMROOT=$PWD/macos/build" \
  -only-testing:GhosttyTests/ClaudeSessionScannerTests \
  -only-testing:GhosttyTests/RecoveredStoresTests \
  -skip-testing:GhosttyUITests test -quiet
```

本轮测试命令退出码 0，4 项测试通过，同时完成 Debug 应用编译。已有并发及调试符号警告仍存在。编译和单元测试不代表真实音频、远程服务及原包交互已经验收。

## arm64 Release 候选构建

2026-10-13 新增统一入口：

```sh
bash reverse-engineering/build-release.sh
```

该入口先生成 ReleaseFast 的本机 arm64 `GhosttyKit.xcframework`，再以项目已有的 ReleaseLocal、arm64、部署后处理和符号剥离构建应用，最后执行深度签名校验。ReleaseLocal 为无开发者证书的本地候选启用 `disable-library-validation`，使同为临时签名的 Sparkle 可被加载；正式开发者签名／公证仍应使用 Release。产物为 `macos/build/ReleaseLocal/Ghostty.app`。

未指定 `ARCHS=arm64` 时，项目默认同时请求 x86_64，但当前恢复框架仅有 arm64，会在链接阶段失败。当前候选因此只支持 Apple Silicon；Intel／通用框架仍是 RELEASE-01 的未完成兼容项。Sparkle 2.9.0 源码及许可证已保存到 `macos/Dependencies/Sparkle`，Xcode 使用项目内相对路径；依赖解析和 Debug arm64 构建通过。

通用框架已进行两种受控尝试：Command Line Tools SDK 在框架生成 iOS 切片时返回 `DarwinSdkNotFound`；完整 Xcode SDK 则出现 `_abort`、`_dispatch_*` 等 Darwin 系统符号未定义，与早期工具链限制一致。两次均在底层框架阶段停止，未产生通用候选。正式脚本保持已验证的 native arm64 路径；不继续无新证据盲试。

同日发现普通 Release 在无有效开发者签名证书时虽然能构建并通过 `codesign --verify`，实际启动会因 Sparkle 与主程序的库验证 Team ID 不一致而失败。`build-release.sh` 因此使用项目既有 ReleaseLocal 配置；重新构建后深度签名校验和真实进程启动通过。正式对外签名／公证应继续使用 Release 配置和同一开发者身份，不能把 ReleaseLocal 当作公证产物。

## 候选包

`build-and-pack.sh` 调用唯一 ReleaseLocal 构建入口并生成不覆盖既有文件的版本化 ZIP；`build-pro-cn.sh` 不再自动删除 `/Applications` 中的应用，只转入安全打包流程。

2026-10-13 候选：`dist/Ghostty-Pro-CN-1.6.0-20261013.1-arm64.zip`，SHA-256 `cd5ca0ff11dd10dd7965d69d56b93aeedc1963a2c6b37d77bd68cbf1e3910e4b`。已独立解包并通过深度签名、版本号和进程启动检查；仅为 Apple Silicon 本地临时签名候选，尚未完成原包全部 UI／真实流程、Intel、开发者签名和公证验收。

2026-10-13 更新候选：`dist/Ghostty-Pro-CN-1.6.0-20261013.2-arm64.zip`，SHA-256 `fcbec1d9489ba95c0cabf2514ac860ea066b4de21dd811eb617c160b25847b38`。完整非 UI XCTest 286 项通过；候选经独立解包、深度签名、版本号、私钥／本机路径扫描及 3 秒启动检查。该包仍为 Apple Silicon 本地临时签名候选，限制同上。

2026-10-13 最新候选：`dist/Ghostty-Pro-CN-1.6.0-20261013.3-arm64.zip`，SHA-256 `9793907b7da0026fc7d9eec25995ea4e5d0f695e5e4c0e03dfaf57c49342c7ad`。完整非 UI XCTest 288 项通过；独立验证目录 `/tmp/ghostty-release-verify-3.TUrTSJ` 的深度签名、版本号、私钥／本机路径扫描及 3 秒启动通过。该包仍为 Apple Silicon 本地临时签名候选，限制同上。

2026-10-13 当前最新候选：`dist/Ghostty-Pro-CN-1.6.0-20261013.4-arm64.zip`，SHA-256 `1519e69e8ca9aecc0f2b5fe451f2dec71161416ddaffc9f2df398d3ccdf2acb4`。Xcode 结果包确认 288 次非 UI 测试通过、0 失败、1 项条件跳过；独立验证目录 `/tmp/ghostty-release-verify-4.gncbv1` 的深度签名、版本号、私钥／本机路径扫描及 3 秒启动通过。该包仍为 Apple Silicon 本地临时签名候选，限制同上。
