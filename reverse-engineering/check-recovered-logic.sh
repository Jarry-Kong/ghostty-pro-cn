#!/bin/bash
# 不启动应用、不改真实会话、不发声或联网；不能替代完整验收。
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/.."
task_check_dir=$(mktemp -d /tmp/ghostty-recovered-logic.XXXXXX)
trap 'rm -rf "$task_check_dir"' EXIT
run_check() {
    local task_check_name="$1"
    shift
    xcrun swiftc "$@" -o "$task_check_dir/$task_check_name"
    "$task_check_dir/$task_check_name"
}
task_scanner=macos/Sources/Features/SessionLibrary/ClaudeSessionScanner.swift
run_check title "$task_scanner" reverse-engineering/check-session-title.swift
run_check rename "$task_scanner" macos/Sources/Features/SessionLibrary/ClaudeSessionRenamer.swift reverse-engineering/check-session-rename.swift
run_check claude macos/Sources/Features/SessionLibrary/ClaudeSessionProcesses.swift reverse-engineering/check-session-process.swift
run_check reply "$task_scanner" macos/Sources/Features/Voice/ClaudeReplyReader.swift macos/Sources/Features/Voice/ClaudeReplyLocator.swift reverse-engineering/check-latest-reply.swift
run_check cleaner macos/Sources/Features/Voice/VoiceSettings.swift macos/Sources/Features/Voice/SpeechTextCleaner.swift reverse-engineering/check-speech-cleaner.swift
run_check retention macos/Sources/Features/Voice/VoiceHistoryRetention.swift reverse-engineering/check-history-retention.swift
run_check lock macos/Sources/Features/Voice/SpeechSegment.swift macos/Sources/Features/Voice/VoiceHistoryEntry.swift macos/Sources/Features/Voice/VoiceHistoryStore.swift reverse-engineering/check-history-lock.swift
echo '七组检查通过；窗口、真实声音、真实会话启动、录音实际清理、远程合成及整体验收不在此脚本覆盖范围内。'
