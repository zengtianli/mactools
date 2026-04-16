#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title yabai-restart
# @raycast.mode fullOutput
# @raycast.icon 🪟
# @raycast.packageName Window Manager
# @raycast.description 重启 Yabai 窗口管理服务
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_python "window/yabai.py" restart "$@"
