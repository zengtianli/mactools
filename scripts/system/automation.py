#!/usr/bin/env python3
"""Personal launchd tasks and a symlink workspace; no copied schedules."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

HOME = Path.home()
AGENTS = HOME / 'Library/LaunchAgents'
DOMAIN = f'gui/{os.getuid()}'
PREFIXES = ('com.tianli.', 'cyou.tianli.', 'com.notifhub.')
REPO = Path(__file__).resolve().parents[2]


def launch(*args, check=True):
    result = subprocess.run(['/bin/launchctl', *map(str, args)], capture_output=True, text=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'launchctl: {result.returncode}')
    return result


def tasks():
    result = {}
    for path in sorted(AGENTS.glob('*.plist')):
        if not path.name.startswith(PREFIXES):
            continue
        data = plistlib.loads(path.read_bytes())
        label = data['Label']
        if not label.startswith(PREFIXES) or label in result:
            raise ValueError(f'任务标识异常或重复：{path}')
        result[label] = (path, data)
    return result


def select(name, items):
    name = name.removesuffix('.plist')
    matches = [label for label in items if label == name or any(label == p + name for p in PREFIXES)]
    if len(matches) != 1:
        raise ValueError(f'任务不存在或名称不唯一：{name}；请用 list 查看完整名称。')
    return matches[0]


def loaded(label):
    result = launch('print', f'{DOMAIN}/{label}', check=False)
    if result.returncode and 'Could not find service' not in result.stderr:
        raise RuntimeError(result.stderr.strip() or '无法查询 launchd 服务')
    return None if result.returncode else result.stdout


def disabled():
    output = launch('print-disabled', DOMAIN).stdout
    return dict((label, state in ('true', 'disabled')) for label, state in re.findall(r'"([^"]+)"\s*=>\s*(true|false|enabled|disabled)', output))


def state(label, data, overrides):
    info = loaded(label)
    off = overrides.get(label, data.get('Disabled', False))
    if info is None:
        return '已暂停' if off else '未加载'
    running = re.search(r'^\s*state = running\s*$', info, re.M)
    return ('运行中' if running else '已加载·等待') + ('（已禁用）' if off else '')


def control(action, label, path, data):
    target = f'{DOMAIN}/{label}'
    info = loaded(label)
    if action == 'pause':
        launch('disable', target)
        if info is not None:
            launch('bootout', target)
    elif action == 'resume':
        launch('enable', target)
        if info is None:
            launch('bootstrap', DOMAIN, path)
    elif action == 'reload':
        if disabled().get(label, data.get('Disabled', False)):
            raise ValueError('任务已暂停；需要恢复时使用 resume。')
        if info is not None:
            launch('bootout', target)
        launch('bootstrap', DOMAIN, path)
    elif action == 'run':
        if disabled().get(label, data.get('Disabled', False)):
            raise ValueError('任务已暂停；先 resume 再 run。')
        if info is None:
            launch('bootstrap', DOMAIN, path)
        # Do not kill an already running update/report process.
        launch('kickstart', target)
    print(f'{label}: {state(label, data, disabled())}')
    if action == 'run':
        print('已提交运行请求；完成结果请查看 show 中的日志。')


def install():
    hub = HOME / 'Dev/jobs'
    links = {
        'ctl': Path(__file__).resolve(),
        'README.md': REPO / 'docs/automation.md',
        'CLAUDE.md': REPO / 'docs/jobs/CLAUDE.md',
        'HARNESS.md': HOME / 'Dev/tools/cc-home/HARNESS.md',
        'handoffs': REPO / 'docs/jobs/handoffs',
        'launchagents': AGENTS,
        'updates/always_latest.py': REPO / 'bin/always_latest.py',
        'updates/brew_maintain.py': REPO / 'bin/brew_maintain.py',
        'projects/mactools': REPO,
        'projects/dev-tools': HOME / 'Dev/tools/dev',
        'projects/notifhub': HOME / 'Apps/cli/notifhub',
        'projects/investment': HOME / 'investment/options/robinhood',
        'projects/kb': HOME / 'Dev/tools/kb',
    }
    # Check every destination before writing any link; preserve existing user files.
    for name, source in links.items():
        dest = hub / name
        if not source.exists():
            raise ValueError(f'源不存在：{source}')
        if os.path.lexists(dest) and not (dest.is_symlink() and dest.resolve() == source.resolve()):
            raise ValueError(f'目标已有其他内容，未覆盖：{dest}')
    for name, source in links.items():
        dest = hub / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.is_symlink():
            dest.symlink_to(source, target_is_directory=source.is_dir())
    print(f'管理入口：{hub}；未更改任何任务的排程或启停状态。')


def main():
    parser = argparse.ArgumentParser(description='个人自动化管理：更新、报告、同步、检查、通知等 launchd 任务')
    parser.add_argument('action', choices=['list', 'show', 'pause', 'resume', 'run', 'reload', 'install'])
    parser.add_argument('task', nargs='?', help='完整 Label 或去掉前缀的短名，例如 always-latest')
    args = parser.parse_args()
    if args.action == 'install':
        install()
        return
    items = tasks()
    if args.action == 'list':
        overrides = disabled()
        for label, (_, data) in items.items():
            print(f'{label:42} {state(label, data, overrides)}')
        print(f'共 {len(items)} 个个人任务；已加载不代表最近一次业务执行成功。')
        return
    if not args.task:
        parser.error('此操作需要指定 task')
    label = select(args.task, items)
    path, data = items[label]
    if args.action == 'show':
        print(f'{label}: {state(label, data, disabled())}\n配置：{path}\n实际文件：{path.resolve()}')
        for key in ['Program', 'ProgramArguments', 'WorkingDirectory', 'StartCalendarInterval', 'StartInterval', 'RunAtLoad', 'KeepAlive', 'WatchPaths', 'StandardOutPath', 'StandardErrorPath']:
            if key in data:
                print(f'{key}: {data[key]}')
        info = loaded(label)
        if info:
            for line in info.splitlines():
                if re.match(r'\s*(state|pid|runs|last exit code|last terminating signal) =', line):
                    print(line.strip())
        if label in ('com.tianli.reports', 'com.tianli.reminders'):
            receipt = HOME / 'Library/Application Support/AutomationGroups' / (label.split('.')[-1] + '.json')
            print(f'分任务回执：{receipt}')
            if receipt.exists():
                for name, entry in json.loads(receipt.read_text()).get('tasks', {}).items():
                    print(f'  {name}: {entry["status"]}, exit={entry.get("exit_code", "未结束")}；日志：{HOME}/Library/Logs/{name}.log / {name}.err')
    else:
        control(args.action, label, path, data)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, plistlib.InvalidFileException) as exc:
        print(f'错误：{exc}', file=sys.stderr)
        sys.exit(1)
