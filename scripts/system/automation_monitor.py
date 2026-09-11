#!/usr/bin/env python3
"""Live view and notifications over existing launchd jobs; never runs business jobs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

import automation as auto
from automation_report import META, schedule

HERE = Path(__file__).resolve().parent
ROOT = auto.HOME / 'Library/Application Support/AutomationMonitor'
LABEL = 'com.tianli.automation-monitor'
PORT = 8798
URL = f'http://127.0.0.1:{PORT}'
APP = auto.REPO / 'build/Automation Monitor.app'
MODES = {'all': '启动、进度、结束', 'result': '仅结束与异常', 'errors': '仅异常', 'silent': '只在工作台显示'}
IMPORTANT = {'com.tianli.optionsdesk-daily', 'com.tianli.reports', 'com.tianli.reminders', 'com.tianli.always-latest'}
NAMES = {'com.tianli.md-index-graph': '文档关系图', 'com.tianli.resource-watch': '资源监控'}
SUBTASKS = {'weekly-reports': '周报', 'monthly-reports': '月报', 'acad-due': '学术期限', 'cases-due': '案件期限', 'client-due': '客户期限'}


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    temp.chmod(0o600)
    temp.replace(path)


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def tail(path, limit=262144):
    if not path or not Path(path).is_file():
        return ''
    with Path(path).open('rb') as f:
        f.seek(0, 2)
        f.seek(max(0, f.tell() - limit))
        return f.read().decode('utf-8', errors='replace')


def last_steps(text):
    # Ignore an earlier attempt's green steps when the current attempt starts again.
    segments = re.split(r'\n执行：[^\n]*review_auto\.py[^\n]*\n', text)
    for line in reversed(segments[-1].splitlines()):
        if line.startswith('@@STEP@@ '):
            try:
                obj = json.loads(line[len('@@STEP@@ '):])
                return [dict(name=s['name'], done=bool(s['done']), status='ok' if s['done'] else 'pending') for s in obj['steps'] if not s.get('skipped')]
            except (ValueError, KeyError, TypeError):
                continue
    return []


def file_steps(path):
    """Deployment output can push the last progress record beyond a log tail."""
    if not path.exists():
        return []
    with path.open('rb') as f:
        f.seek(0, 2)
        pos, carry = f.tell(), b''
        while pos:
            length = min(pos, 65536)
            pos -= length
            f.seek(pos)
            lines = (f.read(length) + carry).split(b'\n')
            carry = lines.pop(0) if pos else b''
            for raw in reversed(lines):
                line = raw.decode('utf-8', errors='replace')
                if line.startswith('@@STEP@@ '):
                    steps = last_steps(line)
                    if steps:
                        return steps
                if line.startswith('执行：') and 'review_auto.py' in line:
                    return []
    return []


def launch_snapshot():
    result = auto.launch('list').stdout
    states = {}
    for line in result.splitlines()[1:]:
        parts = line.split(None, 2)
        if len(parts) == 3:
            pid, code, label = parts
            states[label] = {'pid': int(pid) if pid.isdigit() else None, 'exit_code': int(code)}
    return states


def investment(row, home, now):
    folder = home / 'Library/Application Support/InvestmentDaily'
    receipts = sorted(folder.glob('????-??-??.json'))
    if not receipts:
        row['detail'] = '尚无运行回执'
        return
    path = receipts[-1]
    state = read_json(path)
    row.update(period=path.stem, receipt=str(path), url=state.get('url'), steps=file_steps(path.with_suffix('.log')))
    today = dt.datetime.fromtimestamp(now, ZoneInfo('America/New_York')).date().isoformat()
    pending = state.get('scheduled_retry_at') and state.get('attempts', 0) == 0 and state.get('retry_after', 0) > now
    active = bool(row['pid']) and path.stem == today and not state.get('complete') and not pending
    row['run_key'] = f"{path.stem}:{state.get('attempts', 0)}:{len(state.get('retry_history', []))}"
    row['evidence'] = '投资复盘业务回执与逐步核验'
    if state.get('complete'):
        row.update(status='success', phase='已发布并核验', detail='文章与票据日报已发布并核验', error=None)
    elif active:
        # execute() sets this deadline once at start; failures are handled below.
        if state.get('retry_after'):
            row['started_at'] = state['retry_after'] - 1800
        text = tail(path.with_suffix('.log'))
        commands = re.findall(r'^执行：(.+)$', text, re.M)
        command = commands[-1] if commands else ''
        phase = '生成与自审'
        for token, name in [('blog_readability_gate', '检查正文与配图'), ('sync_market_reads', '同步盘面数据'), ('push_quant_db', '同步盘面数据'), ('git ', '保存文章与配图'), ('blog_publish.py publish', '发布与线上核验')]:
            if token in command:
                phase = name
        row.update(status='running', phase=phase, detail='生成完成后自动发布、核验并通知', error=None)
    elif pending:
        row.update(status='waiting', phase='等待定时重试', detail=state['scheduled_retry_at'], error=None)
    elif state.get('error'):
        row.update(status='failed', phase=state.get('stage', '未完成'), detail='本期尚未发布完成', error=state['error'])
    else:
        row.update(status='interrupted', phase='上次运行未完成', detail='进程已停止，未收到完成回执')
    row['updated_at'] = path.with_suffix('.log').stat().st_mtime if path.with_suffix('.log').exists() else path.stat().st_mtime
    row['schedule'] = '每个美股交易日实际收盘后 1 小时'


def grouped(row, home, now):
    name = row['id'].split('.')[-1]
    path = home / 'Library/Application Support/AutomationGroups' / f'{name}.json'
    data = read_json(path)
    if not data:
        return
    row.update(receipt=str(path), run_key=str(data.get('started_at')), started_at=data.get('started_at'), updated_at=data.get('finished_at', path.stat().st_mtime), evidence='分项执行回执')
    row['steps'] = [dict(name=SUBTASKS.get(key, key), done=val.get('status') == 'ok', status=val.get('status', 'pending')) for key, val in data.get('tasks', {}).items()]
    names = ['weekly-reports', 'monthly-reports'] if name == 'reports' else ['acad-due', 'cases-due', 'client-due']
    for key in names:
        if key not in data.get('tasks', {}):
            row['steps'].append(dict(name=SUBTASKS[key], done=False, status='pending'))
    status = data.get('status')
    current = next((s['name'] for s in row['steps'] if s['status'] == 'running'), None)
    if status == 'running' and row['pid']:
        row.update(status='running', phase=current or '检查任务', detail='顺序处理各分项，一项失败后继续其余项')
    elif status == 'running' or status == 'interrupted':
        row.update(status='interrupted', phase='分项未完成', detail='进程已停止，回执未结束')
    elif status == 'failed':
        failed = [s['name'] for s in row['steps'] if s['status'] != 'ok']
        row.update(status='failed', phase='需要处理', detail='；'.join(failed) + '未完成')
    else:
        row.update(status='success', phase='各分项检查已结束', detail='各分项退出码为 0；未到报告周期时不生成文章')
    # Hourly due checks are not report generation. Do not announce a quick no-op.
    row['quiet_check'] = name == 'reports' and (data.get('finished_at') or now) - data.get('started_at', now) < 10


def updates(row, home, now):
    files = sorted((home / 'Library/Application Support/AutomationUpdates').glob('????????-??????.log'))
    if not files:
        return
    path = files[-1]
    text = tail(path)
    stages = re.findall(r'^--- (.+) ---$', text, re.M)
    row.update(run_key=path.stem, updated_at=path.stat().st_mtime, receipt=str(path), evidence='更新日志与进程退出状态')
    row['steps'] = [dict(name=name, done=False, status='pending') for name in ['Homebrew 更新', 'npm 全局软件更新']]
    if row['status'] == 'running':
        row['phase'] = stages[-1] if stages else '准备更新'
        for step in row['steps']:
            if step['name'] == row['phase']:
                step['status'] = 'running'
        row['detail'] = '正在更新；需要管理员权限时沿用原授权提示'


def collect(home=auto.HOME, now=None):
    now = now or time.time()
    live = launch_snapshot()
    disabled = auto.disabled()
    rows = []
    for label, (path, data) in auto.tasks().items():
        if label == LABEL:
            continue
        found = live.get(label, {})
        pid, code = found.get('pid'), found.get('exit_code')
        off = disabled.get(label, data.get('Disabled', False))
        status = 'paused' if off else 'unloaded' if label not in live else 'running' if pid else 'failed' if code else 'waiting'
        if status == 'running' and data.get('KeepAlive'):
            status = 'service'
        meta = META.get(label, (NAMES.get(label, label), '后台服务', '后台自动任务', ''))
        row = dict(id=label, name=meta[0], group=meta[1], schedule=schedule(data), status=status, phase='', detail=meta[2], pid=pid, exit_code=code, steps=[], run_key=str(pid) if pid else None, evidence='进程状态', error=None, started_at=None, updated_at=None)
        row['default_mode'] = 'all' if label in IMPORTANT else 'errors'
        try:
            if not off:
                if label == 'com.tianli.optionsdesk-daily':
                    investment(row, home, now)
                elif label in ('com.tianli.reports', 'com.tianli.reminders'):
                    grouped(row, home, now)
                elif label == 'com.tianli.always-latest':
                    updates(row, home, now)
        except (OSError, ValueError, KeyError, TypeError) as exc:
            row.update(status='unknown', phase='状态读取失败', error=str(exc), detail='无法确认业务进度')
        if row['status'] == 'failed' and not row.get('phase'):
            row.update(phase='上次进程异常退出', detail=f'退出码 {code}；需要检查任务日志')
        if row['status'] == 'waiting' and code == 0 and not row.get('phase'):
            row['phase'] = '等待下一次检查'
        row['done'] = sum(bool(s['done']) for s in row['steps'])
        row['total'] = len(row['steps'])
        rows.append(row)
    return rows


def transition(old, new):
    """A progress counter is never treated as publication success."""
    status = new['status']
    if not old:
        return 'running' if status == 'running' else None
    if status in ('failed', 'interrupted', 'unknown'):
        signature = (status, new.get('error'), new.get('phase'))
        previous = (old['status'], old.get('error'), old.get('phase'))
        return 'failed' if signature != previous else None
    if status == 'running':
        if old['status'] != 'running' or old.get('run_key') != new.get('run_key') or old.get('quiet_check') and not new.get('quiet_check'):
            return 'running'
        if (old.get('phase'), old.get('done')) != (new.get('phase'), new.get('done')):
            return 'progress'
    if status == 'success' and (old['status'] != 'success' or old.get('run_key') != new.get('run_key')):
        return 'success'
    if old['status'] == 'running' and status == 'waiting':
        return 'ended'
    return None


def should_notify(mode, event):
    return mode == 'all' or mode == 'result' and event in ('success', 'ended', 'failed') or mode == 'errors' and event == 'failed'


class Monitor:
    def __init__(self, root=ROOT, notify=True):
        self.root, self.notify = root, notify
        self.lock = threading.RLock()
        self.stop = threading.Event()
        self.pool = ThreadPoolExecutor(max_workers=1)
        self.settings = read_json(root / 'settings.json')
        history = read_json(root / 'events.json')
        self.events = history.get('events', [])
        self.previous = history.get('previous', {})
        self.snapshot = {'tasks': [], 'events': self.events, 'updated_at': None, 'error': None, 'modes': MODES}
        self.first = True

    def send(self, event, row):
        labels = {'running': '开始运行', 'progress': '进度更新', 'success': '已完成', 'ended': '本轮已结束', 'failed': '需要处理'}
        title = f"{row['name']} · {('正在运行' if event.get('already_running') else labels[event['type']])}"
        progress = f"{row['done']}/{row['total']} 项 · " if row['total'] else ''
        message = progress + (row.get('phase') or row['detail'])
        args = [sys.executable, str(auto.REPO / 'bin/task_notify.py'), '--key', 'automation-' + row['id'], '--title', title, '--message', message, '--fingerprint', event['id'], '--url', APP.as_uri(), '--open-only']
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=70)
            outcome = 'sent' if result.returncode == 0 else 'failed'
        except (OSError, subprocess.TimeoutExpired):
            outcome = 'failed'
        with self.lock:
            event['notification'] = outcome
            save(self.root / 'events.json', {'events': self.events, 'previous': self.previous})

    def refresh(self):
        rows = collect()
        now = time.time()
        changed = False
        pending = []
        with self.lock:
            for row in rows:
                old = self.previous.get(row['id'])
                row['mode'] = self.settings.get(row['id'], row['default_mode'])
                if row['status'] == 'running':
                    same = old and old['status'] == 'running' and old.get('run_key') == row.get('run_key')
                    row['observed_start'] = old.get('observed_start', now) if same else now
                    row['elapsed'] = max(0, int(now - (row.get('started_at') or row['observed_start'])))
                event_type = transition(old, row)
                # Fresh install: show existing history without replaying old failure alerts.
                if event_type:
                    fingerprint = f"{row['id']}:{row.get('run_key')}:{event_type}:{row.get('phase')}:{row['done']}:{row.get('error')}"
                    eid = hashlib.sha256(fingerprint.encode()).hexdigest()[:24]
                    if not any(e['id'] == eid for e in self.events):
                        event = dict(id=eid, task=row['id'], name=row['name'], type=event_type, at=now, phase=row.get('phase') or row['detail'], done=row['done'], total=row['total'], notification='silent', already_running=old is None and event_type == 'running')
                        self.events.insert(0, event)
                        changed = True
                        recent = any(e['task'] == row['id'] and e['id'] != eid and e['notification'] in ('pending', 'sent') and now - e['at'] < 30 for e in self.events)
                        if self.notify and should_notify(row['mode'], event_type) and not (row.get('quiet_check') and event_type != 'failed') and not (event_type == 'progress' and recent):
                            event['notification'] = 'pending'
                            pending.append((event, dict(row)))
                if old is None:
                    changed = True
                self.previous[row['id']] = row
            self.events[:] = [e for e in self.events[:200] if now - e['at'] < 14 * 86400]
            self.snapshot = dict(tasks=rows, events=self.events, updated_at=now, error=None, modes=MODES)
            if changed:
                save(self.root / 'events.json', {'events': self.events, 'previous': self.previous})
        for event, row in pending:
            self.pool.submit(self.send, event, row)

    def loop(self):
        while not self.stop.is_set():
            parent = os.environ.get('AUTOMATION_MONITOR_PARENT_PID')
            if parent and os.getppid() != int(parent):
                os._exit(0)
            try:
                self.refresh()
            except Exception as exc:
                with self.lock:
                    self.snapshot['error'] = str(exc)
            self.stop.wait(5)


def handler(monitor):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, code, body, kind='application/json; charset=utf-8'):
            raw = json.dumps(body, ensure_ascii=False).encode() if not isinstance(body, bytes) else body
            self.send_response(code)
            self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'")
            self.end_headers()
            self.wfile.write(raw)

        def allowed(self, mutation=False):
            host = self.headers.get('Host', '')
            origin = self.headers.get('Origin')
            expected = f'http://{host}'
            return host in (f'127.0.0.1:{PORT}', f'localhost:{PORT}') and (not mutation or origin == expected)

        def do_GET(self):
            if not self.allowed():
                return self.reply(403, {'error': '仅本机访问'})
            path = urlsplit(self.path).path
            if path == '/':
                return self.reply(200, {'app': str(APP), 'message': '进度在 Mac 菜单栏的自动化中查看'})
            if path == '/api/state':
                with monitor.lock:
                    return self.reply(200, monitor.snapshot)
            self.reply(404, {'error': '不存在'})

        def do_POST(self):
            if not self.allowed(mutation=True):
                return self.reply(403, {'error': '请求来源不匹配'})
            if self.path != '/api/settings':
                return self.reply(404, {'error': '不存在'})
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length < 4096:
                    raise ValueError('请求过长或为空')
                obj = json.loads(self.rfile.read(length))
                with monitor.lock:
                    if obj.get('task') not in monitor.previous or obj.get('mode') not in MODES:
                        raise ValueError('任务或提醒方式无效')
                    monitor.settings[obj['task']] = obj['mode']
                    save(monitor.root / 'settings.json', monitor.settings)
                    for row in monitor.snapshot['tasks']:
                        if row['id'] == obj['task']:
                            row['mode'] = obj['mode']
                self.reply(200, {'ok': True})
            except (ValueError, TypeError) as exc:
                self.reply(400, {'error': str(exc)})
    return Handler


def install():
    path = auto.AGENTS / f'{LABEL}.plist'
    source = auto.REPO / 'deploy' / f'{LABEL}.plist'
    if os.path.lexists(path) and path.resolve() != source.resolve():
        raise ValueError('已有其他来源的监控配置，未覆盖')
    if not path.is_symlink():
        path.symlink_to(source)
    if auto.loaded(LABEL) is None:
        auto.launch('enable', f'{auto.DOMAIN}/{LABEL}')
        auto.launch('bootstrap', auto.DOMAIN, path)
    print(f'菜单栏自动化已启用：{APP}')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--install', action='store_true')
    p.add_argument('--once', action='store_true')
    p.add_argument('--no-notify', action='store_true')
    args = p.parse_args()
    if args.install:
        install()
        return
    if args.once:
        print(json.dumps(collect(), ensure_ascii=False, indent=2))
        return
    monitor = Monitor(notify=not args.no_notify)
    server = ThreadingHTTPServer(('127.0.0.1', PORT), handler(monitor))
    thread = threading.Thread(target=monitor.loop, daemon=True)
    thread.start()
    try:
        server.serve_forever()
    finally:
        monitor.stop.set()
        server.server_close()


if __name__ == '__main__':
    main()
