#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title yabai-float
# @raycast.mode fullOutput
# @raycast.icon 🪟
# @raycast.packageName Window Manager
# @raycast.description 切换当前窗口的浮动/平铺状态
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_python "window/yabai.py" float "$@"
