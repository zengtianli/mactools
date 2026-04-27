#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Launch Gov DingTalk
# @raycast.mode silent
# @raycast.icon 💬
# @raycast.packageName Apps
# @raycast.description 启动政务钉钉应用，已运行则跳过
source ~/Dev/devtools/lib/log_usage.sh

# 检查是否已经在运行
if pgrep -f "DingTalkGov" > /dev/null; then
    echo "政务钉钉已在运行"
    exit 0
fi

# 启动政务钉钉
/opt/homebrew/bin/wine ~/.wine/drive_c/Program\ Files\ \(x86\)/DingTalkGov/DingTalkGovLauncher.exe &

echo "政务钉钉启动中..."
