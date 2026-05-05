#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Mailroom · Pending Failures
# @raycast.mode fullOutput
# @raycast.icon ⚠️
# @raycast.packageName Mailroom
# @raycast.description 列 actions_log 失败待重试的条目

cd ~/Dev/mailroom || exit 1
sqlite3 data/mail.db <<EOF
.mode column
.headers on
SELECT msg_id, action, status, substr(error,1,60) as error_excerpt, ts
FROM actions_log
WHERE status='failed'
ORDER BY ts DESC LIMIT 30;
EOF
