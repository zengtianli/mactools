#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title yabai-org
# @raycast.mode fullOutput
# @raycast.icon 🪟
# @raycast.packageName Window Manager
# @raycast.description 通过临时切换 bsp 模式自动整理当前桌面的窗口布局
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_python "window/yabai.py" org "$@"
