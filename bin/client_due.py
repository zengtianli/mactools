#!/Users/tianli/Dev/.venv/bin/python3
"""仅从明确在办的本地业务台账提醒；不推断历史日期、回款或完成状态。"""
import argparse
from collections import Counter
from datetime import date, timedelta
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import yaml
import task_notify

ACTIVE = {'open', 'pending', 'in_progress', 'todo', '进行中', '未完成', '待交付', '待处理'}
FINISHED = {'done', 'completed', 'closed', 'cancelled', '已完成', '已交付', '已验收', '已关闭', '已取消', '已归档'}
RECEIVABLE = {'receivable', '应收', '应收款', '回款'}
UNPAID = {'unpaid', 'pending_payment', '未付', '未收', '未收款', '待收款', '未回款'}
EXCLUDED = {'.git', '.claude', '.venv', 'node_modules', '_archive', '09-归档', 'vendor', 'inbox'}


def completed(value):
    value = str(value or '').strip().lower()
    return value in FINISHED or any(value.startswith(word + sep) for word in FINISHED for sep in (' ', ' ·', '，', '（'))


def evaluate(row, source, today, days, kind='delivery', parent_status=''):
    name = str(row.get('name') or row.get('party') or '').strip()
    status = str(row.get('status') or '').strip().lower()
    if not name:
        return None, '空标题占位'
    if completed(status) or completed(parent_status):
        return None, '已完成或已关闭'
    if kind == 'receivable':
        if str(row.get('kind', '')).strip().lower() not in RECEIVABLE or status not in UNPAID:
            return None, '未明确应收且未付'
    elif status not in ACTIVE and str(parent_status).strip().lower() not in ACTIVE:
        return None, '在办状态不明确'
    raw = row.get('due_date') if kind == 'receivable' else row.get('deadline')
    try:
        due = date.fromisoformat(str(raw))
    except (ValueError, TypeError):
        return None, '缺少有效明确日期'
    evidence = row.get('file') if kind == 'receivable' else row.get('source_file')
    if kind == 'receivable' and not evidence:
        return None, '应收缺少依据文件'
    if evidence:
        ep = Path(evidence).expanduser()
        if not ep.is_absolute():
            ep = source.parent / ep
        if not ep.is_file():
            return None, '依据文件不存在'
    if due > today + timedelta(days=days):
        return None, '不在提醒窗口'
    ident = f'{source}|{kind}|{row.get("id", name)}|{due}'
    return {'key': 'client-due-' + hashlib.sha256(ident.encode()).hexdigest()[:20],
            'name': name, 'kind': kind, 'due': due.isoformat(), 'status': status or parent_status,
            'source': str(source), 'evidence': str(evidence or source), 'fingerprint': ident}, None


def scan(roots, today, days):
    counts, reasons, items = Counter(), Counter(), []
    def walk_error(error):
        raise error
    for root in roots:
        if not root.is_dir():
            raise ValueError(f'扫描根不存在：{root}')
        counts['roots'] += 1
        for base, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
            dirs[:] = [d for d in dirs if d not in EXCLUDED and not d.startswith('.') and not (Path(base)/d).is_symlink()]
            for filename in ('.work.yaml', 'registry.db'):
                if filename not in files:
                    continue
                path = Path(base) / filename
                if path.is_symlink():
                    continue
                counts[filename] += 1
                if filename == '.work.yaml':
                    data = yaml.safe_load(path.read_text()) or {}
                    parent = (data.get('identity') or {}).get('status') or data.get('status', '')
                    rows = data.get('deliverables') or []
                    kind = 'delivery'
                else:
                    with sqlite3.connect(path.as_uri() + '?mode=ro', uri=True) as con:
                        con.row_factory = sqlite3.Row
                        exists = con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='contracts'").fetchone()
                        if not exists:
                            reasons['数据库没有合同表'] += 1
                            continue
                        rows = [dict(r) for r in con.execute('SELECT * FROM contracts')]
                    parent, kind = '', 'receivable'
                if not rows:
                    reasons['空台账'] += 1
                for row in rows:
                    counts['records'] += 1
                    item, reason = evaluate(row, path, today, days, kind, parent)
                    if item:
                        items.append(item)
                    else:
                        reasons[reason] += 1
    if not counts['.work.yaml'] and not counts['registry.db']:
        raise ValueError('扫描范围没有业务台账，拒绝报告检查成功')
    return {'coverage': dict(counts), 'skipped': dict(reasons), 'eligible': items}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, action='append')
    p.add_argument('--today', type=date.fromisoformat, default=date.today())
    p.add_argument('--days', type=int, default=14)
    p.add_argument('--dry-run', action='store_true')
    a = p.parse_args(argv)
    if a.days < 0:
        p.error('--days must be nonnegative')
    roots = a.root or [Path.home()/name for name in ('Work', 'Ghostwriting', 'School', 'Money')]
    result = scan(roots, a.today, a.days)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if a.dry_run:
        return 0
    rc, active = 0, set()
    for item in result['eligible']:
        active.add(item['key'])
        title = '客户回款待处理' if item['kind'] == 'receivable' else '客户交付待处理'
        detail = task_notify.paths(item['key'])[1].with_suffix('.source.txt')
        detail.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        detail.write_text(f'{title}\n事项：{item["name"]}\n到期：{item["due"]}\n状态：{item["status"]}\n台账：{item["source"]}\n依据：{item["evidence"]}\n仅提醒本人，不联系客户。\n')
        detail.chmod(0o600)
        code = task_notify.main(['--key', item['key'], '--title', title, '--message', f'{item["name"]} · {item["due"]} 到期；点击查看依据', '--details', str(detail), '--fingerprint', item['fingerprint']])
        rc = rc or code
    # Only reconcile after a complete successful scan; errors never clear prior notices.
    if task_notify.ROOT.exists():
        for state in task_notify.ROOT.glob('*.json'):
            old = json.loads(state.read_text())
            key = old.get('key', '')
            if key.startswith('client-due-') and key not in active and not old.get('resolved'):
                rc = task_notify.main(['--key', key, '--clear']) or rc
    return rc


if __name__ == '__main__':
    raise SystemExit(main())
