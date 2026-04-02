#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title dingtalk_gov
# @raycast.mode fullOutput
# @raycast.icon 💼
# @raycast.packageName Apps
# @raycast.description 启动政务钉钉（DingTalkGov）

source "$(dirname "$0")/../lib/run_python.sh" && run_shell "system/dingtalk_gov.sh" "$@"
