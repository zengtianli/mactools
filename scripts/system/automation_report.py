#!/usr/bin/env python3
"""Render the local automation inventory and evidence-backed consolidation review."""
import argparse
from datetime import datetime
from html import escape as esc
from pathlib import Path
import re
import shlex
import sys
from zoneinfo import ZoneInfo

import automation as auto

sys.path.insert(0, str(auto.HOME / 'Dev/tools/dev/lib'))
from html_shell import shared_head, SORTABLE_BLOCK

META = {
    'com.tianli.reports': ('周报 + 月报', '报告', '每小时分别检查周/月到期；业务状态、重试与分项日志独立', '已合并 2→1'),
    'com.tianli.reminders': ('晨间到期提醒', '提醒', '学术/案件 30 天 + 客户 14 天；逐源执行、逐项通知', '已合并 3→1'),
    'com.notifhub.daemon': ('通知采集', '通知', '监听本机通知并增量入库', '保留独立'),
    'com.notifhub.publish': ('通知云同步', '通知', '本地生成页面（禁用 LLM）后同步云端', '保留独立'),
    'com.notifhub.queue': ('通知队列', '通知', '处理通知系统自己的作业队列', '保留独立'),
    'com.notifhub.summarize': ('通知总结', '通知', '总结最近两天，调用模型', '保留独立'),
    'com.tianli.acad-due': ('学术到期提醒', '提醒', '未来 30 天；复用 due_notify → acad 检查器', '可统一入口'),
    'com.tianli.cases-due': ('案件到期提醒', '提醒', '未来 30 天；复用 due_notify → cases 检查器', '可统一入口'),
    'com.tianli.client-due': ('客户交付与回款', '提醒', '未来 14 天；要求明确在办、未付及依据', '可统一入口'),
    'com.tianli.always-latest': ('软件自动更新', '更新', '统一执行 Homebrew 维护 + npm 全局更新', '已共用入口'),
    'com.tianli.weekly-reports': ('三类周报', '报告', '美西周日 08:00 到期；每小时检查及开机补跑', '可统一入口'),
    'com.tianli.monthly-reports': ('三类月报', '报告', '美西每月 2 日 08:00 到期；每小时检查及开机补跑', '可统一入口'),
    'com.tianli.optionsdesk-daily': ('投资每日复盘', '投资', '按交易日历，收盘后 1 小时执行；当日成功不重复', '保留独立'),
    'com.tianli.optionsdesk-close': ('旧收盘触发', '投资', '与现行投资任务指向同一个 daily_auto.sh', '优先归档'),
    'com.tianli.auto-git-sync': ('Git 自动同步', '同步', 'git_smart_push.py --simple', '保留暂停'),
    'com.tianli.cc-pulse-import': ('Claude 历史导入', '同步', 'kb/bin/cc.py import --full；不代表 Codex 历史', '保留暂停'),
    'com.tianli.daily-health': ('开发环境健康检查', '检查', '软链、导入、路径和 shebang 等检查', '恢复前再评估'),
    'com.tianli.paths-audit': ('路径一致性检查', '检查', 'paths audit --strict + scan-dead --strict', '恢复前再评估'),
    'com.tianli.downloads-router': ('下载收件整理', '本机作业', '本地下载管线；有自己的并发锁', '保留独立'),
    'com.tianli.mac-agent': ('Mac 远程接单', '本机作业', '已汇总公众号与 SOP 两条队列，各自处理异常', '已共用入口'),
    'com.tianli.qinglong-ckwatch': ('青龙登录监视', '青龙', '检查 Cookie 与漏跑；容器内签到由青龙调度', '保留独立'),
    'cyou.tianli.sm-autodeploy': ('私档站自动部署', '发布', '文件变化触发；当前已暂停', '保留暂停'),
    'cyou.tianli.testflight-expiry': ('TestFlight 到期检查', '检查', '每周检查测试版本到期情况', '保留独立'),
}

CSS = '''
:root{--bg:#f5f6f8;--panel:#fff;--border:#dce2e7;--fg:#202d3b;--mute:#627180;--link:#14675c;--green:#157f65;--amber:#a66117;--purple:#526882}
body{font-size:15px;line-height:1.65}.wrap{max-width:none;padding:26px 34px 55px;margin:0}h1,h2,h3{color:var(--fg)}h1{font-size:36px;border:0;margin:4px 0 8px;letter-spacing:-1px}h2{border:0;padding:0;font-size:23px;margin:30px 0 12px}h3{margin:0 0 8px;font-size:18px}p{margin:8px 0}.eyebrow{font-size:12px;letter-spacing:2px;color:var(--link);font-weight:700}.muted,.meta{color:var(--mute)}.meta{font-size:12px}.hero{display:flex;justify-content:space-between;gap:30px;align-items:center}.hero-copy{max-width:900px}.hub{white-space:nowrap;background:#eaf2ef;border:1px solid #c9ded6;border-radius:12px;padding:18px 22px}.hub code{font-size:17px}code,pre{background:#edf1f4;color:#344957}code{overflow-wrap:anywhere}pre{white-space:pre-wrap;word-break:break-word;font-size:12px}.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:23px 0}.metric{background:white;padding:16px 20px;border:1px solid var(--border);border-radius:12px}.metric b{font-size:32px;line-height:1.1;display:block}.metric span{font-size:13px;color:var(--mute)}.cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}.card{background:white;border:1px solid var(--border);border-radius:12px;padding:19px}.card.primary{border-top:4px solid #1b8068;padding-top:16px}.tag{display:inline-block;border-radius:6px;padding:2px 7px;font-size:12px;background:#edf1f5;color:#596978;margin-bottom:9px}.tag.green{background:#e7f3ed;color:#17694e}.tag.amber{background:#fff0db;color:#93601f}.impact{font-size:12px;font-weight:600;color:#526882}.card p{font-size:14px}.evidence{font-size:12px;margin-top:12px;border-top:1px solid #edf0f3;padding-top:10px}summary{cursor:pointer;color:var(--link);font-weight:600}details[open] summary{margin-bottom:8px}.evidence a{display:block;overflow-wrap:anywhere}.note{padding:14px 18px;border-left:3px solid #98aea7;background:#eef3f1;margin:18px 0;color:#48625b;font-size:13px}.status{display:inline-block;white-space:nowrap;border-radius:20px;padding:3px 9px;background:#e7f3ed;color:#17694e;font-size:12px}.status.off{background:#edf0f3;color:#66727e}.status.run{background:#e1effa;color:#27638d}table{background:white;font-size:13px;margin:0}td{border-left:0;border-right:0;padding:13px 12px}th{background:#f0f3f6;padding:12px;white-space:nowrap}td:first-child{min-width:185px}td:nth-child(3){min-width:170px}td:nth-child(4){min-width:230px;max-width:360px}td:last-child{min-width:150px;max-width:300px}td small{display:block;font-size:11px;color:var(--mute);overflow-wrap:anywhere}.copy{border:1px solid #cbd8d3;border-radius:6px;padding:6px 10px;background:white;color:#226c57;cursor:pointer;font:inherit;font-size:12px;margin-top:6px}.copy:hover{background:#eaf3ee}.controls{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.refresh{margin-top:24px;padding:18px;background:white;border:1px solid var(--border);border-radius:12px}.refresh pre{margin-bottom:0}.footer{font-size:12px;color:var(--mute);margin-top:20px}#toast{position:fixed;bottom:22px;left:50%;transform:translateX(-50%);padding:10px 18px;border-radius:10px;background:#254b40;color:white;box-shadow:0 4px 16px #0002;z-index:100;max-width:90vw}#toast:empty{display:none}.cc-q{background:white}.cc-sc{border-radius:10px;border:1px solid var(--border)}
@media(max-width:1000px){.cards{grid-template-columns:repeat(2,minmax(0,1fr))}.hero{display:block}.hub{display:inline-block;margin-top:12px}}
@media(max-width:600px){.wrap{padding:20px 16px 40px}h1{font-size:30px}.cards{grid-template-columns:1fr}.metrics{grid-template-columns:repeat(2,1fr);gap:9px}.metric{padding:12px}.hero-copy{width:100%}}
'''


def link(path, title):
    return f'<a href="{esc(Path(path).as_uri(), quote=True)}">{esc(title)}</a>'


def evidence(paths):
    return '<details class="evidence"><summary>查看依据与源文件</summary>' + ''.join(link(auto.HOME / p, title) for p, title in paths) + '</details>'


def schedule(data):
    parts = []
    if data.get('KeepAlive'):
        parts.append('常驻，退出后重启')
    if 'StartInterval' in data:
        seconds = data['StartInterval']
        parts.append(f'每 {seconds // 60} 分钟' if seconds % 60 == 0 else f'每 {seconds} 秒')
    intervals = data.get('StartCalendarInterval', [])
    if isinstance(intervals, dict):
        intervals = [intervals]
    for item in intervals:
        if set(item) == {'Minute'}:
            parts.append(f'每小时 {item["Minute"]:02d} 分')
        else:
            prefix = '每天 '
            if 'Weekday' in item:
                prefix = '周' + '日一二三四五六日'[item['Weekday']] + ' '
            if 'Day' in item:
                prefix = f'每月 {item["Day"]} 日 '
            parts.append(prefix + f'{item.get("Hour", 0):02d}:{item.get("Minute", 0):02d}')
    if data.get('WatchPaths'):
        parts.append('监视文件变化')
    if data.get('RunAtLoad'):
        parts.append('加载时执行')
    return '；'.join(parts) or '手动 / 其他触发'


def copy_button(command, label='复制查看命令'):
    return f'<button class="copy" data-copy="{esc(command, quote=True)}">{label}</button>'


def generate(output):
    tasks = auto.tasks()
    overrides = auto.disabled()
    states = {label: auto.state(label, data, overrides) for label, (_, data) in tasks.items()}
    paused = sum('已暂停' in s for s in states.values())
    active = sum('已加载' in s or '运行中' in s for s in states.values())
    local = datetime.now().astimezone()
    stamp = local.astimezone(ZoneInfo('Asia/Shanghai')).strftime('%Y-%m-%d %H:%M:%S 北京时间')
    cards = [
        ('已归档', '旧投资触发配置', '旧 optionsdesk-close 已退出 LaunchAgents，部署源移入 retired。现行 optionsdesk-daily 独立运行，继续按交易日历与收盘后一小时判断；投资逻辑未改。', '配置 2 → 1；原本暂停项减少 1 个', 'primary', [('investment/options/robinhood/deploy/retired/com.tianli.optionsdesk-close.plist', '已归档的旧触发源'), ('investment/options/robinhood/deploy/com.tianli.optionsdesk-daily.plist', '现行触发配置'), ('Dev/jobs/archive/consolidation-20260908-200803/README.md', '原状态与回退入口')]),
        ('已合并', '周报 + 月报的调度', '统一为 reports，每小时整点及加载时顺序检查周报、月报。继续使用原 weekly_reports 引擎与全局发布锁；一项失败继续下一项，分项写回执。', '调度 2 → 1；周/月状态、重试和日志保留', 'primary', [('Dev/tools/mactools/scripts/system/grouped_tasks.py', '两组调度薄层'), ('Dev/tools/mactools/deploy/com.tianli.reports.plist', '统一报告 plist'), ('Library/Application Support/AutomationGroups/reports.json', '最近逐项运行结果')]),
        ('已合并', '三类到期提醒', '统一为 reminders，每日本机时间 09:10 及加载时，依次检查学术、案件、客户。逐源记录错误，逐条通知去重；各类到期规则和业务证据要求保留。', '调度 3 → 1；学术/案件 30 天，客户 14 天', 'primary', [('Dev/tools/mactools/deploy/com.tianli.reminders.plist', '晨间统一 plist'), ('Dev/tools/mactools/bin/due_notify.py', '学术与案件适配器'), ('Dev/tools/mactools/bin/client_due.py', '客户交付 / 回款判定'), ('Library/Application Support/AutomationGroups/reminders.json', '最近逐项运行结果')]),
        ('先决定是否恢复', '健康检查 + 路径检查', '两个任务都已暂停，软链和硬编码路径检查有部分重叠。若恢复，可统一检查报告入口；保留各检查器的范围和退出码，先验证旧入口仍适用。', '此时合并不会减少任何运行负担', '', [('Dev/tools/dev/lib/tools/sites/health_check.py', '健康检查项：软链 / 导入 / 路径 / shebang'), ('Dev/tools/dev/lib/tools/ssot/paths.py', '路径审计、死引用与软链检查')]),
        ('保持独立', '通知的采集 / 队列 / 总结 / 同步', '常驻采集、1 分钟队列、5 分钟同步、1 小时模型总结承担不同职责。云同步显式使用 --no-llm。合并进程会让慢模型或网络失败影响快链路。', '可以共用日志展示，继续分别启停与恢复', '', [('Library/LaunchAgents/com.notifhub.summarize.plist', '总结任务排程'), ('.local/lib/notifhub/sync_cloud.py', '云同步：无 LLM 生成 + HTTPS 上传'), ('Library/LaunchAgents/com.notifhub.daemon.plist', '常驻采集')]),
        ('已经合并到位', '软件更新 + Mac 接单', 'always_latest 已汇总 Homebrew 与 npm，并统一锁、日志和失败通知。mac-agent 已汇总公众号和 SOP 接单，分别捕获错误。两组用途不同，保持各自入口。', '更新耗时长，继续与报告、提醒分开', '', [('Dev/tools/mactools/bin/always_latest.py', '软件维护总入口'), ('Dev/tools/dev/lib/tools/media/mac_agent.py', '两条接单链及独立错误处理')]),
    ]
    card_html = ''
    for tag, title, body, impact, style, refs in cards:
        color = 'green' if style else ('amber' if '可以' in tag or '恢复' in tag else '')
        card_html += f'<article class="card {style}"><span class="tag {color}">{tag}</span><h3>{title}</h3><p>{body}</p><p class="impact">{impact}</p>{evidence(refs)}</article>'
    rows = []
    for label, (path, data) in tasks.items():
        title, group, purpose, suggestion = META.get(label, (label, '待归类', '新增任务，尚未审阅业务实现', '待审阅'))
        state = states[label]
        cls = 'off' if '已暂停' in state or '未加载' in state else ('run' if '运行中' in state else '')
        info = auto.loaded(label)
        match = re.search(r'^\s*last exit code = (.+)$', info or '', re.M)
        last = match.group(1) if match else '未读取到'
        command = shlex.join(data.get('ProgramArguments', [data.get('Program', '')]))
        detail = f'<details><summary>配置 / 日志 / 命令</summary>{link(path, "打开 plist")}{link(path.resolve(), " · 实际文件")}<pre>{esc(command)}</pre><p>最近退出码：{esc(last)}</p>'
        for key in ['StandardOutPath', 'StandardErrorPath']:
            if data.get(key):
                detail += f'<p>{key}：{link(data[key], data[key])}</p>'
        detail += f'<pre>{esc(str({k: data[k] for k in ["StartInterval", "StartCalendarInterval", "KeepAlive", "RunAtLoad", "WatchPaths"] if k in data}))}</pre></details>'
        rows.append(f'<tr><td><b>{esc(title)}</b><small>{esc(label)}</small></td><td>{esc(group)}<br><span class="status {cls}">{esc(state)}</span></td><td>{esc(schedule(data))}</td><td>{esc(purpose)}<br><span class="tag">{esc(suggestion)}</span></td><td>{detail}{copy_button("~/Dev/jobs/ctl show " + label)}</td></tr>')
    body = f'''<main class="wrap"><header class="hero"><div class="hero-copy"><div class="eyebrow">LOCAL AUTOMATION · CONSOLIDATED</div><h1>自动化，已经归到一起</h1><p class="lead">周/月报合并为 reports，三类到期提醒合并为 reminders；旧投资触发已归档。通知、更新、投资继续独立运行。</p><p class="meta">只读快照 · {stamp} · Mac 本地 {local.strftime('%Y-%m-%d %H:%M %Z %z')}</p></div><div class="hub"><div class="meta">统一管理目录</div><code>cd ~/Dev/jobs</code><br>{copy_button('cd ~/Dev/jobs && ./ctl list', '复制进入与查看命令')}</div></header>
<div class="metrics"><div class="metric"><b>{len(tasks)}</b><span>个人 launchd 配置</span></div><div class="metric"><b>{active}</b><span>已加载（含正在运行）</span></div><div class="metric"><b>{paused}</b><span>其余暂停项保留原状</span></div><div class="metric"><b>−4</b><span>本次 21 → 17 项 · 归档 1 / 合并 2 组</span></div></div>
<h2>合并结果与保留的边界</h2><div class="cards">{card_html}</div><div class="note">2026-09-08 已安装新组：首次真实执行中，周报、月报及三类提醒共 5 项均退出 0，原报告状态文件逐字节未变。失败、超时与缺失命令的隔离测试通过；历史配置及回退脚本保存在 jobs/archive。检查类的暂停状态未改。</div>
<h2>全部任务与管理入口</h2><p class="muted">可搜索名称、状态、类别；点击表头排序。时刻栏为 Mac 本地触发时间，业务脚本的到期时间另见“用途与判断”。</p><table id="tasks"><thead><tr><th>任务</th><th>类别 / 状态</th><th>系统触发</th><th>用途与判断</th><th>证据与管理</th></tr></thead><tbody>{''.join(rows)}</tbody></table>
<section class="refresh"><h3>在目录里控制，按需刷新页面</h3><p>页面复制命令，不直接执行后台任务。暂停会停止当前进程；恢复可能立即触发 RunAtLoad 任务。</p><pre>cd ~/Dev/jobs
./ctl show always-latest
./ctl show reports
./ctl show reminders
./ctl pause always-latest
./ctl resume always-latest
./ctl run always-latest</pre><p>重新读取本机状态并生成这张页面：</p><pre>python3 ~/Dev/tools/mactools/scripts/system/automation_report.py</pre>{copy_button('python3 ~/Dev/tools/mactools/scripts/system/automation_report.py', '复制刷新命令')}</section>
<footer class="footer">范围：当前用户 LaunchAgents 中的 com.tianli.* / cyou.tianli.* / com.notifhub.*。未盘点 VPS、青龙容器内任务、系统级 LaunchDaemons 与第三方软件自带更新。已加载和退出码均不等于业务成功。页面生成只读本机状态；HTML 是采集时的快照，刷新浏览器不会重新查询 launchd。</footer></main><div id="toast" role="status" aria-live="polite"></div>'''
    js = '''<script>document.addEventListener('click',async e=>{const b=e.target.closest('[data-copy]');if(!b)return;const text=b.dataset.copy;let ok=false;try{await navigator.clipboard.writeText(text);ok=true}catch(err){const t=document.createElement('textarea');t.value=text;t.style.position='fixed';t.style.left='-9999px';document.body.appendChild(t);t.select();ok=document.execCommand('copy');t.remove()}const toast=document.getElementById('toast');toast.textContent=ok?'已复制命令；请在终端执行':'复制失败，请手动选取页面中的命令';clearTimeout(window.toastTimer);window.toastTimer=setTimeout(()=>toast.textContent='',3000)})</script>'''
    html = '<!doctype html><html lang="zh-CN">' + shared_head(title='自动化任务 · 合并建议', extra_css=CSS) + '<body>' + body + SORTABLE_BLOCK + js + '</body></html>'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html)
    print(f'{output}\n{len(tasks)} 项；{active} 已加载；{paused} 已暂停；{stamp}')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, default=auto.HOME / 'Dev/jobs/index.html')
    generate(p.parse_args().out)
