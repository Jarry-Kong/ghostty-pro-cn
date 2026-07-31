#!/usr/bin/env bash
#
# 编译当前最新代码 + 打包成可发送的 zip（放桌面）
# 用法：bash build-and-pack.sh
#
# 做三件事：
#   1. 用 zig 编译核心库 libghostty（ReleaseFast）
#   2. 用 Xcode 编译 macOS app（先补齐 Sparkle 等依赖，避免依赖缺失的坑）
#   3. 打包成带日期的 zip 放到桌面（ad-hoc 签名，对方右键可开）
# 不安装到 /Applications、不动系统里现有的 Ghostty。

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

echo "========================================"
echo " 第 1 步 / 共 3 步：编译核心库 (zig)"
echo "========================================"
zig build -Demit-xcframework=true -Doptimize=ReleaseFast
echo "✅ 核心库编译完成"
echo ""

echo "========================================"
echo " 第 2 步 / 共 3 步：编译 macOS app (Xcode)"
echo " 这一步最慢，可能 5-15 分钟，请耐心等，别关窗口"
echo "========================================"
cd macos
# 先确保 Sparkle 等依赖下载好（这是之前编译失败的真正原因）
echo "-> 正在补齐依赖(Sparkle 等)..."
xcodebuild -resolvePackageDependencies \
  -project Ghostty.xcodeproj -scheme Ghostty -derivedDataPath build
# 正式编译（不带 clean，避免误删刚下好的依赖）
echo "-> 正在编译 app..."
xcodebuild \
  -project Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal -derivedDataPath build -arch arm64 \
  build
echo "✅ app 编译完成"
echo ""

echo "========================================"
echo " 第 3 步 / 共 3 步：打包成 zip 到桌面"
echo "========================================"
# 定位刚编出来的 app
APP="$REPO/macos/build/Build/Products/ReleaseLocal/Ghostty.app"
if [ ! -d "$APP" ]; then
  echo "❌ 没找到编译产物：$APP"
  echo "   编译可能没成功，请把上面的日志截图发我。"
  exit 1
fi
# ad-hoc 重新签名（确保对方电脑右键能打开）
echo "-> 正在签名..."
codesign --force --deep --sign - "$APP" 2>/dev/null || true
# 打包
OUT="$HOME/Desktop/Ghostty二开-最新-$(date +%Y%m%d).zip"
rm -f "$OUT"
echo "-> 正在打包..."
ditto -c -k --keepParent "$APP" "$OUT"

echo ""
echo "========================================"
echo " ✅✅✅ 全部完成！"
echo "========================================"
echo "版本号：$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '读取失败')"
echo "名  称：$(defaults read "$APP/Contents/Info.plist" CFBundleName 2>/dev/null || echo '读取失败')"
echo "签  名：$(codesign -dvv "$APP" 2>&1 | grep -i 'Signature=' || echo '未知')"
echo "安装包：$OUT"
ls -lh "$OUT"
echo ""
echo "桌面上这个 zip 就是含你最新代码的安装包，确认版本号对了就能发给同事。"
