#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title sys-app-launcher
# @raycast.mode fullOutput
# @raycast.icon 🚀
# @raycast.packageName System
# @raycast.description Launch essential apps from ~/Desktop/essential_apps.txt
source "$(dirname "$(realpath "$0")")/../lib/run_python.sh" && run_python "system/sys_app_launcher.py" "$@"
