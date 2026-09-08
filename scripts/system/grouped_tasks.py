#!/usr/bin/env python3
"""Two launchd entry points; preserve existing business engines and per-task logs."""
import argparse
from datetime import datetime
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

HOME = Path.home()
REPO = Path(__file__).resolve().parents[2]
STATE = HOME / 'Library/Application Support/AutomationGroups'
LOGS = HOME / 'Library/Logs'
GROUPS = {
    'reports': [
        ('weekly-reports', ['/bin/bash', str(REPO / 'bin/weekly_reports.sh')], 14400),
        ('monthly-reports', ['/bin/bash', str(REPO / 'bin/weekly_reports.sh'), '--frequency', 'monthly'], 14400),
    ],
    'reminders': [
        ('acad-due', ['/opt/homebrew/bin/python3', str(REPO / 'bin/due_notify.py'), '--source', 'acad', '--days', '30'], 1800),
        ('cases-due', ['/opt/homebrew/bin/python3', str(REPO / 'bin/due_notify.py'), '--source', 'cases', '--days', '30'], 1800),
        ('client-due', [str(HOME / 'Dev/.venv/bin/python3'), str(REPO / 'bin/client_due.py')], 1800),
    ],
}


def stop_child(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def run_one(name, command, timeout):
    LOGS.mkdir(parents=True, exist_ok=True)
    with (LOGS / f'{name}.log').open('a') as out, (LOGS / f'{name}.err').open('a') as err:
        out.write(f'\n[grouped task start {datetime.now().astimezone().isoformat()}]\n')
        out.flush()
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=out, stderr=err, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            err.write(f'\nTask exceeded {timeout}s; terminating its process group.\n')
            stop_child(process)
            return 124
        except BaseException:
            stop_child(process)
            raise


def save(path, data):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    temp.replace(path)


def run_group(group):
    os.umask(0o077)
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / f'{group}.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(f'{group}: already running')
            return 0
        receipt = {'group': group, 'started_at': time.time(), 'status': 'running', 'tasks': {}}
        path = STATE / f'{group}.json'
        save(path, receipt)
        for name, command, timeout in GROUPS[group]:
            entry = {'started_at': time.time(), 'status': 'running'}
            receipt['tasks'][name] = entry
            save(path, receipt)
            try:
                rc = run_one(name, command, timeout)
            except Exception as exc:
                rc = 1
                entry['error'] = str(exc)
            except BaseException:
                entry.update(status='interrupted', finished_at=time.time())
                receipt.update(status='interrupted', finished_at=time.time())
                save(path, receipt)
                raise
            entry.update(exit_code=rc, status='ok' if rc == 0 else 'failed', finished_at=time.time())
            save(path, receipt)
            print(f'{group}/{name}: exit {rc}', flush=True)
        failed = any(item['exit_code'] != 0 for item in receipt['tasks'].values())
        receipt.update(status='failed' if failed else 'ok', finished_at=time.time())
        save(path, receipt)
        return int(failed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('group', choices=GROUPS)
    parser.add_argument('--check', action='store_true', help='Print child commands without running them')
    args = parser.parse_args()
    if args.check:
        print(json.dumps(GROUPS[args.group], ensure_ascii=False, indent=2))
        return 0
    def terminated(signum, frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, terminated)
    return run_group(args.group)


if __name__ == '__main__':
    raise SystemExit(main())
