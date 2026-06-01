#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Set External Display
# @raycast.mode fullOutput
# @raycast.icon 🖥️
# @raycast.packageName System
# @raycast.description Set external display resolution (auto-detects external monitor)
# @raycast.argument1 { "type": "dropdown", "placeholder": "Resolution", "data": [{"title":"4K (3840x2160)","value":"4k"},{"title":"1080p (presentation)","value":"1080"}] }
# 实现：display_set.sh <4k|1080> @ 同目录引擎(合并原 display_1080/display_4k 两条)
exec "$(dirname "$(realpath "$0")")/display_set.sh" "${1:-4k}"
