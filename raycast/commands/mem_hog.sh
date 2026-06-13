#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title 内存大户 Mem Hog
# @raycast.mode fullOutput
# @raycast.icon 🧠
# @raycast.packageName System
# @raycast.description 按 .app 聚合内存占用 top 15 + 诚实建议「该关哪个」(浏览器重启/重型工具退出);只读不杀进程
# @raycast.argument1 { "type": "dropdown", "placeholder": "条数", "optional": true, "data": [{"title":"Top 15","value":"15"},{"title":"Top 25","value":"25"}] }
exec /opt/homebrew/bin/python3 "$HOME/Dev/tools/mactools/bin/mem_hog.py" -n "${1:-15}"
