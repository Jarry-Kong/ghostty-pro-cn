#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${GHOSTTY_RECOVERY_ZIG:-}" ]]; then
  zig_executable="$GHOSTTY_RECOVERY_ZIG"
elif command -v zig >/dev/null 2>&1 && [[ "$(zig version 2>/dev/null)" == "0.15.2" ]]; then
  zig_executable="$(command -v zig)"
else
  zig_executable="${HOME}/Library/Application Support/Ghostty-Recovery/toolchains/zig-aarch64-macos-0.15.2/zig"
fi
optimize="${GHOSTTY_RECOVERY_OPTIMIZE:-Debug}"
framework_target="${GHOSTTY_RECOVERY_XCFRAMEWORK_TARGET:-native}"
test -x "$zig_executable"
test "$("$zig_executable" version)" = 0.15.2
case "$optimize" in
  Debug|ReleaseSafe|ReleaseFast|ReleaseSmall) ;;
  *) echo "GHOSTTY_RECOVERY_OPTIMIZE 必须是 Debug、ReleaseSafe、ReleaseFast 或 ReleaseSmall" >&2; exit 2 ;;
esac
case "$framework_target" in
  native|universal) ;;
  *) echo "GHOSTTY_RECOVERY_XCFRAMEWORK_TARGET 必须是 native 或 universal" >&2; exit 2 ;;
esac
cd "$project_dir"
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
GHOSTTY_XCODE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
"$zig_executable" build -Demit-xcframework -Demit-macos-app=false -Dxcframework-target="$framework_target" \
  -Doptimize="$optimize" -j4
