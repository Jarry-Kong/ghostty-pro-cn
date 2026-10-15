#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"

bash reverse-engineering/build-release.sh

app="$project_dir/macos/build/ReleaseLocal/Ghostty.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
mkdir -p dist
archive="$project_dir/dist/Ghostty-Pro-CN-${version}-${build}-arm64.zip"
if [[ -e "$archive" ]]; then
  echo "目标包已存在，未覆盖：$archive" >&2
  exit 2
fi
ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
echo "构建包：$archive"
cat "$archive.sha256"
