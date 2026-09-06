#!/usr/bin/env python3
"""Local, clickable task notifications. No network or shell interpolation of content."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time

ROOT = Path(os.environ.get('TASK_NOTIFY_STATE', str(Path.home() / 'Library/Application Support/TaskNotifications')))
NOTIFIER = '/opt/homebrew/bin/terminal-notifier'


def paths(key):
    stem = hashlib.sha256(key.encode()).hexdigest()[:24]
    return ROOT / (stem + '.json'), ROOT / (stem + '.txt')


def save(path, data):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp.chmod(0o600)
    tmp.replace(path)


def eligible(old, fingerprint, now, repeat):
    if old.get('fingerprint') != fingerprint:
        return True
    if old.get('dismissed') or now < old.get('snoozed_until', 0):
        return False
    if old.get('snoozed_until'):
        return True
    return now - old.get('sent_at', 0) >= repeat * 3600


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--key', required=True)
    p.add_argument('--title', default='任务提醒')
    p.add_argument('--message', default='点击查看详情')
    p.add_argument('--details', type=Path)
    p.add_argument('--url')
    p.add_argument('--fingerprint', help='Stable event identity; omit volatile dates/countdowns')
    p.add_argument('--repeat-hours', type=float, default=168)
    p.add_argument('--clear', action='store_true')
    p.add_argument('--interact', action='store_true')
    p.add_argument('--action', choices=['open', 'dismiss', 'snooze'])
    p.add_argument('--dry-run', action='store_true')
    a = p.parse_args(argv)
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    state, detail = paths(a.key)
    if a.interact or a.action:
        old = json.loads(state.read_text())
        action = a.action
        if action in (None, 'open'):
            subprocess.run(['/usr/bin/open', '-a', 'TextEdit', str(detail)], check=True)
            if old.get('url'):
                subprocess.run(['/usr/bin/open', old['url']], check=True)
            if action == 'open':
                return 0
            # argv, not AppleScript source, carries untrusted titles/text.
            script = '''on run argv
tell application "System Events"
activate
set r to display dialog (item 1 of argv) with title "任务提醒" buttons {"本轮不再提醒", "暂停24小时", "保留提醒"} default button "保留提醒" giving up after 120
return button returned of r
end tell
end run'''
            r = subprocess.run(['/usr/bin/osascript', '-e', script, old['title'] + '\n完整结果已在文本窗口打开。\n暂停后将在24小时后的下一次检查提醒。\n本轮不再提醒仅关闭此通知，不更改业务台账。'], capture_output=True, text=True)
            if r.returncode:
                return r.returncode
            action = {'本轮不再提醒': 'dismiss', '暂停24小时': 'snooze'}.get(r.stdout.strip())
        with (ROOT / 'state.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            current = json.loads(state.read_text())
            if current.get('fingerprint') != old.get('fingerprint'):
                return 0
            if action == 'dismiss':
                current['dismissed'] = True
            elif action == 'snooze':
                current['snoozed_until'] = time.time() + 86400
            save(state, current)
        return 0
    with (ROOT / 'state.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = json.loads(state.read_text()) if state.exists() else {}
        group = 'task-' + state.stem
        if a.clear:
            if a.dry_run:
                print('would clear', a.key)
                return 0
            save(state, {'key': a.key, 'resolved': True})
            r = subprocess.run([NOTIFIER, '-remove', group], capture_output=True, text=True, timeout=60)
            if r.returncode:
                print(r.stderr, file=sys.stderr)
            return r.returncode
        body = a.details.read_text() if a.details else a.message
        fingerprint = a.fingerprint or hashlib.sha256((a.title + '\n' + a.message).encode()).hexdigest()
        now = time.time()
        data = dict(old) if old.get('fingerprint') == fingerprint else {}
        data.update(key=a.key, title=a.title, message=a.message, fingerprint=fingerprint, url=a.url)
        if a.dry_run:
            print(json.dumps({'key': a.key, 'send': eligible(old, fingerprint, now, a.repeat_hours), 'title': a.title, 'message': a.message}, ensure_ascii=False))
            return 0
        detail.write_text(a.title + '\n\n' + a.message + '\n\n' + body)
        detail.chmod(0o600)
        save(state, data)
        if not eligible(old, fingerprint, now, a.repeat_hours):
            print('重复提醒已抑制:', a.key)
            return 0
        command = shlex.join([sys.executable, str(Path(__file__).resolve()), '--key', a.key, '--interact'])
        try:
            r = subprocess.run([NOTIFIER, '-title', a.title, '-message', a.message, '-subtitle', '点击查看详情与提醒选项', '-group', group, '-execute', command], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            print('通知工具超时；详情已保存：' + str(detail), file=sys.stderr)
            return 1
        if r.returncode:
            print('通知未送达；详情已保存：' + str(detail) + '\n' + r.stderr, file=sys.stderr)
            return r.returncode
        data.update(sent_at=now, snoozed_until=0)
        save(state, data)
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
