#!/usr/bin/env python3
"""Adapt existing deadline checkers into individual, deduplicated local notifications."""
import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path
import task_notify


def stable(line):
    return re.sub(r'(?:已过期|剩)\s*\d+\s*天|今天', '', line).strip()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source', choices=['acad', 'cases'], required=True)
    p.add_argument('--days', default='30')
    p.add_argument('--today')
    p.add_argument('--dry-run', action='store_true')
    a = p.parse_args()
    home = Path.home()
    if a.source == 'acad':
        cmd = ['/opt/homebrew/bin/python3', str(home / 'Dev/tools/kb/bin/acad.py'), 'due', '--days', a.days]
        title = '学术事项'
    else:
        cmd = ['/opt/homebrew/bin/python3', str(home / 'Archives/ip-legal/.tools/cases_due.py'), '--days', a.days]
        title = '案件事项'
        if a.today:
            cmd += ['--today', a.today]
    r = subprocess.run(cmd, capture_output=True, text=True)
    body = r.stdout + r.stderr
    report = home / 'Library/Logs' / (a.source + '-due-details.txt')
    report.write_text(body)
    report.chmod(0o600)
    lines = [line.strip() for line in r.stdout.splitlines() if '🔴' in line or '🟡' in line]
    common = ['--dry-run'] if a.dry_run else []
    keys = set()
    result = 0
    if r.returncode:
        return task_notify.main(['--key', a.source + '-checker', '--title', title + '检查未完成', '--message', '暂时无法确认期限状态，点击查看原因。', '--details', str(report)] + common) or r.returncode
    if not a.dry_run:
        # Resolve only previously created checker errors, avoiding unnecessary permission calls.
        if task_notify.paths(a.source + '-checker')[0].exists():
            result = task_notify.main(['--key', a.source + '-checker', '--clear'])
    for line in lines:
        identity = stable(line)
        key = a.source + '-due-' + hashlib.sha256(identity.encode()).hexdigest()[:16]
        keys.add(key)
        msg = line + '；点击查看完整依据'
        code = task_notify.main(['--key', key, '--title', title + '待处理', '--message', msg, '--details', str(report), '--fingerprint', identity] + common)
        result = result or code
    if not a.dry_run and task_notify.ROOT.exists():
        import json
        for path in task_notify.ROOT.glob('*.json'):
            old = json.loads(path.read_text())
            key = old.get('key', '')
            if key.startswith(a.source + '-due-') and key not in keys and not old.get('resolved'):
                code = task_notify.main(['--key', key, '--clear'])
                result = result or code
    print(f'{title}: {len(lines)} 项；' + ('预览' if a.dry_run else '已检查'))
    return result


if __name__ == '__main__':
    raise SystemExit(main())
