#!/usr/bin/env python3
"""Evidence-based private weekly reports. Check hourly; publish once per PT week."""
from __future__ import annotations
import argparse
import datetime as dt
import fcntl
import hashlib
import html as html_lib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from zoneinfo import ZoneInfo

HOME = Path.home()
HERE = Path(__file__).resolve().parent
HQ = HOME / 'Dev/tools/dev/lib/tools/cc'
ROOT = HOME / 'Library/Application Support/WeeklyReports'
PT = ZoneInfo('America/Los_Angeles')
KINDS = {'development': '开发周报', 'water': '水利周报', 'investment': '投资周报'}
sys.path.insert(0, str(HQ))
import blog_paths as bp
import blog_publish


def save(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2))
    tmp.chmod(0o600)
    tmp.replace(path)


def period(now):
    """Wall-clock Sunday 08:00 boundaries preserve local time over DST."""
    now = now.astimezone(PT)
    end = dt.datetime.combine(now.date() - dt.timedelta(days=(now.weekday()+1) % 7), dt.time(8), PT)
    if now < end:
        end -= dt.timedelta(days=7)
    return end - dt.timedelta(days=7), end


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), '-c', 'core.quotepath=false', *args], text=True, timeout=45)


def repositories(kind):
    import yaml
    if kind == 'development':
        rows = json.loads((HOME / 'Dev/tools/configs/repo-map.json').read_text())['repos']
        result = {Path(row['local']).expanduser() for row in rows.values()
                       if any(row.get('local', '').startswith(prefix) for prefix in
                              ('~/Dev/tools/', '~/Dev/stations/', '~/Apps/'))}
        # The app catalog aggregator covers new apps absent from the old repo mapping.
        sys.path.insert(0, str(HOME/'Dev/tools/dev/lib/tools/report'))
        from app_registry import enumerate_catalogs
        apps, errors = enumerate_catalogs()
        if errors:
            raise RuntimeError('应用注册表读取失败：'+'；'.join(errors))
        for app in apps:
            directory = Path(app['path']).parent
            if str(directory).startswith((str(HOME/'Apps')+'/', str(HOME/'Dev/stations')+'/')):
                try:
                    result.add(Path(git(directory, 'rev-parse', '--show-toplevel').strip()))
                except subprocess.CalledProcessError:
                    pass  # catalogs without git cannot supply commit evidence
        result.add(HOME/'Dev/stations')
        return sorted(result)
    roots = [HOME / 'Work/projects', HOME / 'Work/shared']
    result = []
    for root in roots:
        catalog = yaml.safe_load((root / 'catalog.yaml').read_text())
        result.extend(root / key for key in catalog['packages'])
    return sorted(set(result))


def collect(kind, start, end):
    records, coverage = [], {'start': start.isoformat(), 'end_exclusive': end.isoformat(), 'scanned': [], 'unavailable': [], 'truncated': []}
    if kind == 'investment':
        for slug in bp.all_slugs():
            post = bp.post(slug)
            if post.site_key != 'options' or slug.startswith('weekly-'):
                continue
            raw = post.zh_md.read_text()
            fm = bp._parse_frontmatter_text(raw)
            try:
                day = dt.date.fromisoformat(str(fm.get('date')))
            except ValueError:
                continue
            if start.date() <= day < end.date():
                records.append({'id': f'post:{slug}', 'title': str(fm.get('title', slug)), 'text': raw[:14000],
                                'source': post.url, 'group': '逐日投资复盘', 'date': str(day)})
        coverage['scanned'] = ['blog_paths:options']
        # Missing daily reviews are disclosed as a source gap, never invented.
        sys.path.insert(0, str(HOME / 'investment/options/src'))
        from quantlab.tcal import is_trading_day, require_calendar_coverage
        seen = {r['date'] for r in records}
        day = start.date()
        while day < end.date():
            require_calendar_coverage(day)
            if is_trading_day(day) and str(day) not in seen:
                coverage['unavailable'].append(f'{day} 逐日投资复盘缺失')
            day += dt.timedelta(days=1)
    else:
        repos = repositories(kind)
        if not repos:
            raise RuntimeError('项目枚举为空，拒绝空集成功')
        for repo in repos:
            try:
                if not repo.is_dir() or Path(git(repo, 'rev-parse', '--show-toplevel').strip()).resolve() != repo.resolve():
                    raise RuntimeError('不存在或不是独立仓')
                if not git(repo, 'rev-list', '--all', '--max-count=1').strip():
                    coverage['scanned'].append(str(repo))
                    continue  # an explicitly empty git repository has no activity
                author = git(repo, 'config', 'user.email').strip()
                if not author:
                    raise RuntimeError('未配置提交者身份，无法区分本人工作与上游变更')
                output = git(repo, 'log', '--fixed-strings', '--author='+author,
                             '--since='+start.isoformat(), '--until='+end.isoformat(),
                             '-n', '81', '--format=%H%x1f%cI%x1f%s%x1f%b%x1e')
                coverage['scanned'].append(str(repo))
                rows = [r.strip('\r\n').split('\x1f', 3) for r in output.split('\x1e') if r.strip()]
                # git timestamp cutoff is inclusive; ensure an exclusive endpoint here.
                rows = [r for r in rows if start <= dt.datetime.fromisoformat(r[1]) < end]
                if len(rows) > 16:
                    coverage['truncated'].append({'repo': str(repo), 'observed_up_to': len(rows), 'included': 16})
                for sha, stamp, subject, body in rows[:16]:
                    names = git(repo, 'show', '--format=', '--name-only', sha).splitlines()
                    text = subject + '\n' + body[:2400] + '\n变更文件：\n' + '\n'.join(names[:20])
                    identity = hashlib.sha256(str(repo).encode()).hexdigest()[:8]
                    records.append({'id': f'git:{identity}:{sha[:12]}', 'title': subject,
                                    'text': text, 'source': str(repo) + ' @ ' + sha[:12],
                                    'group': repo.name, 'date': dt.datetime.fromisoformat(stamp).astimezone(PT).date().isoformat()})
            except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
                coverage['unavailable'].append(f'{repo}: {exc}')
    records.sort(key=lambda r: (r['date'], r['id']))
    if not coverage['scanned']:
        raise RuntimeError('没有成功读取任何来源')
    return records, coverage


def run(args, log, timeout=1800):
    with log.open('a') as out:
        out.write('\n> ' + ' '.join(map(str, args)) + '\n')
        out.flush()
        subprocess.run(list(map(str, args)), stdout=out, stderr=subprocess.STDOUT, check=True, timeout=timeout)


def notice(key, title, message, log, url=None):
    args = [sys.executable, HERE/'task_notify.py', '--key', key, '--title', title,
            '--message', message, '--details', log]
    if url:
        args += ['--url', url, '--open-only']
    subprocess.run(list(map(str, args)), check=True, timeout=75)


def verify(slug):
    post = bp.post(slug)
    fm = bp._parse_frontmatter_text(post.zh_md.read_text())
    if fm.get('private') is not True:
        raise RuntimeError('周报必须明确 private:true')
    body, _ = blog_publish.read_live(slug, '/private-view/'+slug)
    html = body.decode()
    plain = html_lib.unescape(re.sub('<[^>]+>', ' ', html))
    if str(fm['title']) not in html or '本期取材' not in html or str(fm['excerpt']) not in plain:
        raise RuntimeError('线上私密正文未核验通过')
    # Verify source image, not just an HTTP 200 login page.
    image, mime = blog_publish.read_live(slug, fm['image'])
    if len(image) < 1000 or not mime.startswith('image/'):
        raise RuntimeError('线上封面不可读')
    url = post.base_url + '/private-view/' + slug
    # Anonymous visitors must not receive the private report at its real edge URL.
    try:
        with urlopen(Request(url, headers={'User-Agent': 'Mozilla/5.0 (WeeklyReports verify)'}), timeout=30) as response:
            edge = response.read().decode(errors='replace')
            if str(fm['excerpt']) in edge or ('/_gate/' not in response.url and '访问验证' not in edge):
                raise RuntimeError('私密链接未确认访问保护')
    except HTTPError as error:
        if error.code not in (401, 403):
            raise
    return url


def execute(kind, start, end, retry=False):
    folder = ROOT / end.date().isoformat() / kind
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    path, log = folder/'state.json', folder/'run.log'
    state = json.loads(path.read_text()) if path.exists() else {}
    key = f'weekly-{kind}-{end.date()}'
    if state.get('complete'):
        if not state.get('notified'):
            notice(key, KINDS[kind]+'已发布', '过去一周的进展与待办，点击阅读全文', log, state['url'])
            state['notified'] = True
            save(path, state)
        return
    if not retry and (state.get('attempts', 0) >= 2 or time.time() < state.get('retry_after', 0)):
        return
    state.update(attempts=state.get('attempts', 0)+1, retry_after=time.time()+3600, stage='读取本周工作记录')
    state.pop('error', None)
    save(path, state)
    try:
        evidence = folder/'evidence.json'
        if not evidence.exists() or (json.loads(evidence.read_text()).get('coverage', {}).get('unavailable') and not (folder/'rendered.json').exists()):
            records, coverage = collect(kind, start, end)
            save(evidence, {'records': records, 'coverage': coverage})
        data = json.loads(evidence.read_text())
        if not data['records']:
            if data['coverage']['unavailable']:
                evidence.unlink()
                raise RuntimeError('来源有读取缺口，无法把零记录认作本周无工作')
            state.update(complete=True, notified=True, result='本期已扫描，无新增记录；不发空周报')
            save(path, state)
            return
        state['stage'] = '撰写有来源的周报和配图'
        save(path, state)
        from weekly_render import render
        rendered = folder/'rendered.json'
        slug = json.loads(rendered.read_text())['slug'] if rendered.exists() else None
        if slug:
            cached = bp.post(slug)
            if not all((cached.images_dir/name).is_file() for name in ('hero.jpg', 'activity.png', 'groups.png')):
                slug = None
        if not slug:
            slug = render(kind, str(end.date()), data['records'], folder)
        post = bp.post(slug)
        # Scope and gaps are deterministic, not entrusted to a generated summary.
        raw = post.zh_md.read_text()
        if '本期取材' not in raw:
            raw += '\n\n本期取材：'+start.strftime('%Y-%m-%d %H:%M')+' 至 '+end.strftime('%Y-%m-%d %H:%M')+'（美西时间，不含终点）。只反映留有记录的工作；提交不等于交付或验收。\n'
            raw += f"\n本期纳入 {len(data['records'])} 条证据。" + ('每仓最多取最近 16 条。' if kind != 'investment' else '投资总结来自本期逐日复盘。') + '完整来源与覆盖明细保存在本机本期归档。后续建议反映这些记录中的状态，之后的更新不在本期范围内。\n'
            if data['coverage']['unavailable']:
                raw += f"\n取材缺口：{len(data['coverage']['unavailable'])} 项来源未能读取；本期结论不覆盖这些缺口。\n"
            post.zh_md.write_text(raw)
        state['stage'] = '检查与发布私密博客'
        save(path, state)
        run([sys.executable, HQ/'blog_readability_gate.py', post.zh_md], log, 120)
        # The existing publication backup uses explicit pathspecs and never includes unrelated work.
        sys.path.insert(0, str(HOME/'investment/options/robinhood'))
        from review_daily import backup_post
        backup_post(post, log)
        # On a publish-stage retry, deployment may already have succeeded before a later check failed.
        live = False
        if state.get('deploy_attempted'):
            try:
                verify(slug)
                live = True
            except Exception as exc:
                if isinstance(exc, ConnectionError):
                    raise  # SSH connectivity failure: no repeated connection attempts
        if not live:
            state['deploy_attempted'] = True
            save(path, state)
            run([sys.executable, HQ/'blog_publish.py', 'publish', slug], log)
        run([sys.executable, HQ/'blog_private_site.py', 'sync'], log, 180)
        url = verify(slug)
        state.update(complete=True, url=url, slug=slug, stage='已发布并核验', finished_at=dt.datetime.now(PT).isoformat())
        state.pop('error', None)
        save(path, state)
        subprocess.run([sys.executable, str(HERE/'task_notify.py'), '--key', key+'-failed', '--clear'], check=True, timeout=75)
        notice(key, KINDS[kind]+'已发布', '过去一周的进展与待办，点击阅读全文', log, url)
        state['notified'] = True
        save(path, state)
    except Exception as exc:
        log.write_text((log.read_text() if log.exists() else '') + f'\n{state["stage"]}：{type(exc).__name__}: {exc}\n')
        state['error'] = str(exc)
        save(path, state)
        notice(key+'-failed', KINDS[kind]+'需要处理', state['stage']+'未完成，点击查看原因', log)
        raise


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--check', action='store_true')
    p.add_argument('--collect', action='store_true', help='Read-only source inspection; save private evidence snapshot')
    p.add_argument('--kind', choices=KINDS)
    p.add_argument('--retry', action='store_true', help='Explicit retry of the latest due report')
    p.add_argument('--at', help='Aware timestamp for --check only')
    a = p.parse_args(argv)
    if a.at and not a.check:
        p.error('--at only supports --check')
    now = dt.datetime.fromisoformat(a.at) if a.at else dt.datetime.now(PT)
    if now.tzinfo is None:
        p.error('--at needs a timezone')
    start, end = period(now)
    if a.check:
        print(json.dumps({'start': start.isoformat(), 'end': end.isoformat(), 'next': (end+dt.timedelta(days=7)).isoformat()}, ensure_ascii=False))
        return 0
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.umask(0o077)
    with (ROOT/'run.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        errors = []
        for kind in [a.kind] if a.kind else KINDS:
            if a.collect:
                existing = ROOT/str(end.date())/kind/'state.json'
                if existing.exists() and json.loads(existing.read_text()).get('complete'):
                    raise RuntimeError('本期已完成，拒绝覆盖已发布证据归档')
                records, coverage = collect(kind, start, end)
                save(ROOT/str(end.date())/kind/'evidence.json', {'records': records, 'coverage': coverage})
                print(json.dumps({'kind': kind, 'records': len(records), 'coverage': coverage}, ensure_ascii=False))
            else:
                try:
                    execute(kind, start, end, a.retry)
                except Exception as exc:
                    errors.append(f'{kind}: {exc}')
        if errors:
            print('\n'.join(errors), file=sys.stderr)
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
