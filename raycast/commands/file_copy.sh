#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title file-copy
# @raycast.mode fullOutput
# @raycast.icon 📋
# @raycast.packageName Files
# @raycast.description Copy selected file's filename (and optionally content) to clipboard
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title": "Filename Only", "value": "name"}, {"title": "Name + Content", "value": "content"}] }
source "$(dirname "$0")/../lib/run_python.sh" && run_python "file/file_copy.py" "$@"
