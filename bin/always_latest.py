#!/usr/bin/env python3
"""Weekly software maintenance; successful runs are silent, failures have one report."""
import fcntl
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime

BIN = Path(__file__).resolve().parent
STATE = Path.home() / 'Library/Application Support/AutomationUpdates'


def node_bin():
    candidates = list((Path.home() / '.nvm/versions/node').glob('*/bin'))
    return max(candidates, key=lambda p: tuple(map(int, re.findall(r'\d+', p.parent.name)))) if candidates else None


def quarantine_metadata(root, destination):
    """Only Finder metadata in npm package enumeration directories is moved."""
    candidates = [root / '.DS_Store']
    candidates.extend(p / '.DS_Store' for p in root.glob('@*') if p.is_dir())
    moved = []
    for path in candidates:
        if path.is_file():
            target = destination / path.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), target)
            moved.append(str(path))
    return moved


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'running.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('软件更新已在运行，本次不重复启动。')
            return 0
        return maintain()


def maintain():
    stamp = datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')
    log_path = STATE / f'{stamp}.log'
    failures = []
    env = dict(os.environ)
    node = node_bin()
    env['PATH'] = ':'.join(filter(None, [str(node) if node else None, '/opt/homebrew/bin', env.get('PATH', '')]))
    with log_path.open('w') as log:
        def run(label, command):
            print(f'{label}… 日志：{log_path}', flush=True)
            log.write(f'\n--- {label} ---\n')
            log.flush()
            try:
                result = subprocess.run(command, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=10800)
                if result.returncode:
                    failures.append(f'{label}未完成')
                return result.returncode
            except (OSError, subprocess.TimeoutExpired) as exc:
                log.write(f'{exc}\n')
                failures.append(f'{label}未完成')
                return 1
        run('Homebrew 更新', [sys.executable, '-u', str(BIN / 'brew_maintain.py'), '--auto'])
        npm = str(node / 'npm') if node else shutil.which('npm', path=env['PATH'])
        if npm:
            try:
                result = subprocess.run([npm, 'root', '-g'], env=env, capture_output=True, text=True, check=True, timeout=60)
                root = Path(result.stdout.strip())
                if not root.is_absolute() or not root.is_dir():
                    raise ValueError(f'npm 全局目录无效：{root}')
                moved = quarantine_metadata(root, STATE / 'metadata-backups' / stamp)
                log.write(f'已移走 Finder 元数据（可恢复）：{moved}\n')
                run('npm 全局软件更新', [npm, 'update', '-g'])
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                log.write(f'npm 检查失败：{exc}\n')
                failures.append('npm 全局目录检查失败')
        else:
            failures.append('未找到 npm 更新程序')
        log.flush()
    failed_casks = re.findall(r'^\s+([a-z0-9@.+-]+): (?:安装失败|超时)', log_path.read_text(), re.MULTILINE)
    if failed_casks and 'Homebrew 更新未完成' in failures:
        failures[failures.index('Homebrew 更新未完成')] += '（' + '、'.join(failed_casks) + '）'
    notify = [sys.executable, str(BIN / 'task_notify.py'), '--key', 'software-updates']
    if failures:
        details = STATE / 'latest-failure.txt'
        details.write_text('软件更新未全部完成\n\n' + '\n'.join(failures) + '\n\n完整日志：\n' + log_path.read_text())
        notify += ['--title', f'软件更新有 {len(failures)} 项未完成', '--message', '；'.join(failures) + '。点击查看详情。', '--details', str(details)]
    else:
        notify += ['--clear']
    result = subprocess.run(notify, stdin=subprocess.DEVNULL)
    print('软件更新完成。' if not failures else '；'.join(failures), flush=True)
    return 1 if failures or result.returncode else 0


if __name__ == '__main__':
    sys.exit(main())
