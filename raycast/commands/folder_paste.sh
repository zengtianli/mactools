#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title folder_paste
# @raycast.mode fullOutput
# @raycast.icon 📋
# @raycast.packageName Custom
# @raycast.description 将剪贴板中的文件粘贴到 Finder 当前目录
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_shell "file/folder_paste.sh" "$@"
