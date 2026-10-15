#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
echo "为保护现有安装，本脚本不再自动删除或覆盖 /Applications 中的应用。"
echo "将生成独立、带版本与校验值的候选包，由你确认后手动安装。"
exec bash "$project_dir/build-and-pack.sh"
