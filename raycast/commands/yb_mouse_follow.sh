#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title yabai-mouse-follow
# @raycast.mode fullOutput
# @raycast.icon 🖱️
# @raycast.packageName Window Manager
# @raycast.description 切换鼠标是否随窗口焦点移动
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_python "window/yabai.py" mouse "$@"
