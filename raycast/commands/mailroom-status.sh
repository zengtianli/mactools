#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Mailroom · Status
# @raycast.mode fullOutput
# @raycast.icon 📊
# @raycast.packageName Mailroom
# @raycast.description 看 mail.db 分类分布 + 最近一次 run.log

cd ~/Dev/mailroom || exit 1
python3 bin/mail.py stats
echo
echo "## Last run"
tail -1 data/run.log 2>/dev/null | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(json.dumps(d, indent=2, ensure_ascii=False))" 2>/dev/null || tail -1 data/run.log
