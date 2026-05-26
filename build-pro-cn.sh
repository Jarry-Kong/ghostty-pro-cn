#!/usr/bin/env bash
#
# 一键构建并安装「Ghostty Pro 中文版」
#
# 用法： ./build-pro-cn.sh
#
# 这个脚本做四件事：
#   1. 用 ReleaseFast 重新生成 libghostty 的 xcframework
#   2. 用 xcodebuild ReleaseLocal 配置打包 macOS .app
#   3. 把 .app 安装到 /Applications/Ghostty Pro 中文版.app（先删旧的）
#   4. 自动清理所有构建中间产物，注销 LaunchServices 残留
#
# 跑完之后，系统里永远只剩一份「Ghostty Pro 中文版」，不会冒出多余的 Ghostty 图标。

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DST="/Applications/Ghostty Pro 中文版.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

cd "$REPO"

echo "==> [1/4] 用 ReleaseFast 编译 libghostty (zig)"
zig build -Demit-xcframework=true -Doptimize=ReleaseFast

echo "==> [2/4] xcodebuild 打包 macOS .app"
cd macos
xcodebuild \
    -project Ghostty.xcodeproj \
    -scheme Ghostty \
    -configuration ReleaseLocal \
    -derivedDataPath build \
    -arch arm64 \
    clean build > /tmp/ghostty-pro-cn-build.log 2>&1
echo "    完整日志: /tmp/ghostty-pro-cn-build.log"

SRC="$REPO/macos/build/Build/Products/ReleaseLocal/Ghostty.app"
if [ ! -d "$SRC" ]; then
    echo "❌ 构建失败，没找到 $SRC"
    tail -20 /tmp/ghostty-pro-cn-build.log
    exit 1
fi

echo "==> [3/4] 安装到 $DST"
if [ -d "$DST" ]; then
    "$LSREG" -u "$DST" 2>/dev/null || true
    rm -rf "$DST"
fi
cp -R "$SRC" "$DST"

# CFBundleName 已经写在 macos/Ghostty-Info.plist 里，应该是中文版
# 但为了双保险，每次安装都用 PlistBuddy 校正一次
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Ghostty Pro 中文版'" "$DST/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string 'Ghostty Pro 中文版'" "$DST/Contents/Info.plist"

# ad-hoc 重新签名
codesign --force --deep --sign - "$DST" 2>&1 | tail -1

# 注册到 Launch Services
"$LSREG" -f "$DST"

echo "==> [4/4] 清扫构建中间产物（防止 Spotlight 索引到多余的 Ghostty）"
CLEANUP_PATHS=(
    "$REPO/macos/build/Build/Products/ReleaseLocal/Ghostty.app"
    "$REPO/macos/build/Build/Products/Debug/Ghostty.app"
    "$REPO/macos/build/Build/Products/Release/Ghostty.app"
    "$REPO/macos/build/ReleaseLocal/Ghostty.app"
    "$REPO/macos/build/Debug/Ghostty.app"
    "$REPO/macos/build/Release/Ghostty.app"
    "$REPO/zig-out/Ghostty.app"
)
for P in "${CLEANUP_PATHS[@]}"; do
    if [ -d "$P" ]; then
        "$LSREG" -u "$P" 2>/dev/null || true
        rm -rf "$P"
        echo "    清理: $P"
    fi
done

# 最后再扫一遍 LaunchServices，把任何不是 /Applications 下的 Ghostty 都注销
"$LSREG" -dump 2>/dev/null | awk '/path:/ && /[Gg]hostty\.app/ && !/\/Applications\// && !/Sparkle/ && !/Updater/ && !/DockTilePlugin/ {
    for (i=2; i<=NF-1; i++) printf "%s ", $i;
    printf "%s\n", $(NF-1);
}' | while IFS= read -r LEFTOVER; do
    LEFTOVER="${LEFTOVER% }"
    if [ -n "$LEFTOVER" ]; then
        "$LSREG" -u "$LEFTOVER" 2>/dev/null && echo "    注销残留: $LEFTOVER"
    fi
done

echo ""
echo "✅ 完成！「Ghostty Pro 中文版」已就绪。"
echo "   显示名: $(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$DST/Contents/Info.plist")"
echo "   Spotlight 名: $(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$DST/Contents/Info.plist")"
echo "   Bundle ID:   $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$DST/Contents/Info.plist")"
echo ""
echo "   现在 Spotlight 搜 'Ghostty' 应该只显示官方版 + 中文版两个图标。"
