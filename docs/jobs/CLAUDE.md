# jobs · 个人自动化工作台

中文交流。全局规则唯一源为 `/Users/tianli/Dev/tools/cc-home/HARNESS.md`，已加载就不重复读取。此文件是 `~/Dev/jobs` 的项目上下文原版，经软链接接入；Codex 使用原生 CLAUDE.md fallback，不另写一套 AGENTS 规则。

## 用途与入口

这里集中管理本人 Mac 自动更新、报告、提醒、同步与后台作业。`jobs` 是软链接工作台，业务实现保留在所属仓库，不把脚本、配置和业务状态复制成第二份。

- `README.md`：当前操作说明。
- `handoffs/current.md`：最近交接与已验证范围；接续本任务时先读。
- `index.html`：只读任务快照与整理结果，支持搜索、排序、展开依据和复制命令。
- `ctl`：现场读取 launchd 的控制命令。
- `launchagents/`：`~/Library/LaunchAgents` 的实时目录链接。
- `updates/`：软件更新脚本入口；`projects/`：原业务仓库链接。
- `archive/`：可回退的配置整理记录，不能当作活配置重新安装。

## 现行操作

```bash
cd /Users/tianli/Dev/jobs
./ctl list
./ctl show always-latest
./ctl show reports
./ctl show reminders
./ctl pause <任务短名>
./ctl resume <任务短名>
./ctl run <任务短名>
./ctl reload <任务短名>
```

`pause` 持久禁用并停止当前进程；`resume` 恢复，RunAtLoad 任务可能立即执行；`run` 不绕过暂停状态，也不强制重启正在运行的任务；修改 plist 后用 `reload`，已暂停任务不会被它恢复。`ctl` 仅管理 `com.tianli.*`、`cyou.tianli.*`、`com.notifhub.*`。青龙容器内部、VPS 和第三方自带更新使用各自原入口，不从本机列表推断它们的状态。

刷新 HTML（不会执行业务任务）：

```bash
python3 /Users/tianli/Dev/tools/mactools/scripts/system/automation_report.py
```

HTML 是生成时的快照；实际运行状态用 `ctl`。已加载、最近退出码和业务成功分别核验。

## 已确定的管理方式

- 周报和月报共用 `reports`：每小时整点＋加载时，顺序调用原引擎；业务窗口、发布锁、状态、重试与日志独立。具体报告工作走共享 `reports` 技能。
- 学术、案件、客户期限共用 `reminders`：本机每天 09:10＋加载时。学术/案件提前 30 天，客户提前 14 天；逐源执行、逐条通知，不联系客户。不得在合并中改写台账判定或清除失败来源的旧提醒。
- 分组调度一项失败或超时后继续下一项，保留原分项日志和汇总回执。暂停整组会停止组内全部自动执行，手工补单项仍用原业务脚本。
- `optionsdesk-close` 已退役，仅保留现行 `optionsdesk-daily`。勿同时装回旧单项与新分组。
- 通知采集、队列、模型总结、云同步保持独立；软件更新、投资复盘保持独立。其他已暂停任务未获恢复指令时维持原状。
- 软件更新继续按现有 `always-latest` 排程。Homebrew 需要 sudo 时通过 `SUDO_ASKPASS` 弹隐藏密码输入框；取消或 120 秒未响应，本轮不再追问。密码只经管道给 sudo，不存脚本、环境变量、日志、钥匙串或文件。此接口不提供 Touch ID，不配置宽泛 NOPASSWD，也不把整个 brew 作为 root 运行。不要保存或复述聊天中提供的密码。

## 源码、状态与修改落点

统一管理实现原版：`/Users/tianli/Dev/tools/mactools/scripts/system/`，包括 `automation.py`、`automation_report.py`、`grouped_tasks.py`、`update_askpass.py`。更新业务入口为同仓 `bin/always_latest.py`、`bin/brew_maintain.py`。新分组 plist 原版在同仓 `deploy/`，安装到 LaunchAgents 的是软链接。

修改工具前进入原仓读取适用项目指引，查看并保留并发差异；授权范围内按原仓流程检查、提交、推送。其他业务按 `projects/` 指向的仓库上下文执行，尤其不要把投资业务逻辑改在 jobs。

- 分组回执：`~/Library/Application Support/AutomationGroups/{reports,reminders}.json`。
- 周/月报状态：`~/Library/Application Support/WeeklyReports/`；软件更新日志：`~/Library/Application Support/AutomationUpdates/`。
- launchd 和分项日志：`~/Library/Logs/`，具体路径由 `ctl show` 回读。
- 项目上下文原版：`/Users/tianli/Dev/tools/mactools/docs/jobs/CLAUDE.md`；交接原版：同目录 `handoffs/current.md`。编辑前解析软链接，不在 jobs 新建平行副本。
- 工作台链接安装器：`python3 /Users/tianli/Dev/tools/mactools/scripts/system/automation.py install`；只补同源链接，不覆盖其他内容，不改变任务状态。

一般任务只查相关配置、脚本、回执；不因进入工作台就运行全栈检查、全量软件更新或恢复全部暂停任务。共享规则维护走 `harness`，HTML 展示走 `html`，目录依赖迁移走 `workspace`。
