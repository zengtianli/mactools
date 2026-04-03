#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title display_1080
# @raycast.mode fullOutput
# @raycast.icon 📺
# @raycast.packageName Display
# @raycast.description Set external displays to 1080p (1920x1080) for presentation
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_shell "system/display_1080.sh" "$@"
