# 自动化管理入口

进入 `cd ~/Dev/jobs`。青龙等独立自动化作业的真身放在这里；业务仓的任务通过软链接接入，macOS 仍从 `~/Library/LaunchAgents` 加载任务。

在此目录开新会话：项目上下文为 `CLAUDE.md`，最近交接为 `handoffs/current.md`，`HARNESS.md` 链接到全局规则唯一源。上下文与交接原版存于 mactools 的 `docs/jobs/`，通过软链接接入。

可视化清单与合并建议：`~/Dev/jobs/index.html`（只读快照）。刷新数据用 `python3 ~/Dev/tools/mactools/scripts/system/automation_report.py`，然后重新打开页面。

```bash
./ctl list                         # 个人后台任务及当前状态
./ctl show always-latest           # 自动更新的排程、执行入口、日志路径与最近退出码
./ctl pause always-latest          # 持久暂停，并停止当前进程
./ctl resume always-latest         # 恢复排程；RunAtLoad/KeepAlive 任务可能立即执行
./ctl run always-latest            # 立即请求执行，不强制重启正在运行的任务
./ctl reload always-latest         # 修改 plist 后重新加载，会停止当前进程
```

`pause` 会持续到 `resume`，重新登录也不会自行恢复。`run` 不会绕过暂停状态，也不等待业务完成；结果看 `show` 列出的日志。`reload` 保留暂停状态，已暂停任务需明确 `resume`。

软件更新遇到 sudo 时会显示“Homebrew 软件更新授权”的隐藏密码输入框，通过 Homebrew 原生 `SUDO_ASKPASS` 接口完成提权。普通更新不请求密码。取消或 120 秒未响应后，本轮不再弹窗，需权限步骤记录失败，其他可继续的更新照常；下次运行可以重新授权。密码只经管道交给 sudo，不写入脚本、环境变量、日志、钥匙串或临时文件；临时目录只保存取消标记。授权缓存遵循系统 sudo 策略，不承诺跨软件或长时间更新只弹一次。此输入框不提供 Touch ID。

| 入口 | 用途 |
|---|---|
| `launchagents/` | 当前用户的全部 launchd 配置，直接映射系统目录，新增任务自动可见 |
| `updates/` | 自动更新总入口与 Homebrew 维护脚本的链接；日常触发用 `ctl run always-latest` |
| `projects/mactools/` | 更新、周报/月报、到期提醒的实现 |
| `projects/dev-tools/` | Git 同步、健康检查、路径检查、下载整理等实现 |
| `qinglong/` | 青龙项目真身（脚本、配置、容器数据）；本机面板 http://127.0.0.1:5700 |
| `projects/notifhub/` | 通知采集、队列、总结与同步 |
| `projects/investment/` | 投资自动任务 |
| `projects/kb/` | 知识库导入与到期提醒 |

`ctl` 每次现场读取 `com.tianli.*`、`cyou.tianli.*`、`com.notifhub.*`，不维护第二份任务清单。第三方 LaunchAgents 可在 `launchagents/` 查看，但不纳入此命令的启停范围。青龙容器内任务、VPS 调度和第三方软件自带更新仍使用各自原管理入口；`qinglong-ckwatch` 只控制 Cookie 监视任务。

常用短名：`always-latest`（Homebrew 与 npm 全局更新）、`reports`（周报＋月报）、`reminders`（学术＋案件＋客户期限）、`auto-git-sync`、`daily-health`、`paths-audit`、`downloads-router`、`qinglong-ckwatch`。通知任务可用完整名称，例如 `com.notifhub.summarize`。

`reports` 每小时整点和加载时检查，顺序运行周报、月报；各自的业务日期、发布锁、状态、重试与日志不变。`reminders` 每日本机时间 09:10 和加载时检查三类期限，学术/案件仍为 30 天，客户仍为 14 天，通知逐项去重。一项失败继续下一项；报告单项最多 4 小时、提醒单项最多 30 分钟，超时会停止该项并记录失败。

`./ctl show reports` / `./ctl show reminders` 可查看分任务结果。汇总回执在 `~/Library/Application Support/AutomationGroups/{reports,reminders}.json`，原分任务日志仍在 `~/Library/Logs/{weekly-reports,monthly-reports,acad-due,cases-due,client-due}.{log,err}`。暂停组会同时暂停组内全部自动任务；按业务手动补跑继续使用原脚本。

2026-09-08 合并前六份配置及原启停状态保存在 `~/Dev/jobs/archive/consolidation-20260908-200803/`，回退方式见该目录 `README.md`。旧部署源移入各项目 `deploy/retired/`，不再属于安装入口。

排程以 plist 和任务代码的内部条件为准：`StartCalendarInterval` 用 Mac 本地时区，青龙用容器时区；每小时唤醒不等于每小时生成报告。已加载、进程退出码、实际业务成功是不同状态。

修改排程：在 `launchagents/` 找到对应 plist → 编辑前用 `ctl show` 确认其实际文件位置 → 修改 → `plutil -lint launchagents/<文件名>.plist` → `ctl reload <任务名>`。不要移动或删除链接指向的源文件。

重建此工作台：`python3 ~/Dev/tools/mactools/scripts/system/automation.py install`。安装只补齐链接，遇到同名的其他文件会报错，不覆盖用户内容，不变更任务状态。
