#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title file-print
# @raycast.mode fullOutput
# @raycast.icon 🖨️
# @raycast.packageName Files
# @raycast.description Print selected files from Finder using default printer
# @raycast.argument1 { "type": "text", "placeholder": "Copies (default: 1)", "optional": true }
source "$(dirname "$0")/../lib/run_python.sh" && run_python "file/file_print.py" "$@"
