#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title display_4k
# @raycast.mode fullOutput
# @raycast.icon 🖥️
# @raycast.packageName Display
# @raycast.description Set external displays to 4K (3840x2160)
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_shell "system/display_4k.sh" "$@"
