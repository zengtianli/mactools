#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title brew_maintain
# @raycast.mode fullOutput
# @raycast.icon 🍺
# @raycast.packageName System
# @raycast.description Homebrew cask 维护：清理孤儿 + 升级在用
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_python "system/brew_maintain.py" "$@"
