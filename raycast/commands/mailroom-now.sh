#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Mailroom · Run Now
# @raycast.mode fullOutput
# @raycast.icon 📬
# @raycast.packageName Mailroom
# @raycast.description 立即跑一轮邮件聚合（不等 launchd 10min）

source ~/.personal_env 2>/dev/null
cd ~/Dev/mailroom || exit 1
python3 main.py --once 2>&1 | tail -40
