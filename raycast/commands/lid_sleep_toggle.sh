#!/bin/bash

# Raycast parameters
# @raycast.schemaVersion 1
# @raycast.title Toggle Lid Sleep
# @raycast.mode compact
# @raycast.icon 💤
# @raycast.packageName System

# Documentation:
# @raycast.description 切换盒盖睡眠（盒盖时让 Mac 不睡，CC / 长任务继续跑）。会弹密码框（sudo pmset）。
# @raycast.author tianli

source ~/Dev/devtools/lib/log_usage.sh

CURRENT=$(pmset -g | awk '/SleepDisabled/ {print $2}')
[ -z "$CURRENT" ] && CURRENT=0

if [ "$CURRENT" = "1" ]; then
    NEW=0
    MSG="✅ 盒盖会睡眠（已恢复默认）"
else
    NEW=1
    MSG="🔥 盒盖不睡眠 — CC / 长任务继续跑（记得插电、别压被子里）"
fi

if osascript -e "do shell script \"pmset -a disablesleep $NEW\" with administrator privileges" 2>/dev/null; then
    echo "$MSG"
    echo ""
    echo "当前 pmset 状态："
    pmset -g | grep -E "SleepDisabled|^ sleep " | sed 's/^/  /'
else
    echo "❌ 取消或密码错误，未改动"
    exit 1
fi
