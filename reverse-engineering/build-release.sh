#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

GHOSTTY_RECOVERY_OPTIMIZE=ReleaseFast GHOSTTY_RECOVERY_XCFRAMEWORK_TARGET=native \
  bash reverse-engineering/build-core.sh
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
  -configuration ReleaseLocal -destination 'platform=macOS,arch=arm64' \
  "SYMROOT=$project_dir/macos/build" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  DEPLOYMENT_POSTPROCESSING=YES COPY_PHASE_STRIP=YES STRIP_INSTALLED_PRODUCT=YES \
  build -quiet

codesign --verify --deep --strict macos/build/ReleaseLocal/Ghostty.app
file macos/build/ReleaseLocal/Ghostty.app/Contents/MacOS/ghostty
