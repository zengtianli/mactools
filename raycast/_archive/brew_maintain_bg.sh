#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Maintain Homebrew (Background)
# @raycast.mode silent
# @raycast.icon 🍺
# @raycast.packageName System
# @raycast.description Background silent brew upgrade (fire-and-forget), returns <1s without blocking Raycast; log ~/Library/Logs/always-latest.log
source ~/Dev/tools/dev/lib/log_usage.sh

LOG="$HOME/Library/Logs/always-latest.log"
SCRIPT="$HOME/Dev/tools/mactools/raycast/commands/brew_maintain.py"

# 已在后台跑则不重复触发
if pgrep -f "brew_maintain.py --auto" >/dev/null 2>&1; then
    echo "🍺 brew 升级已在后台运行中，不重复触发"
    exit 0
fi

# 完全脱离 Raycast 的后台进程：Raycast 立即返回，升级独立跑（退 Raycast 也不影响）
{
    echo "===== $(date) brew_maintain (raycast 手动后台) ====="
    /opt/homebrew/bin/python3 "$SCRIPT" --auto
    echo "===== done $(date) ====="
} >> "$LOG" 2>&1 &
disown

echo "🍺 brew 升级已在后台开始，日志 ~/Library/Logs/always-latest.log"
