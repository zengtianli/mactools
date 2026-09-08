# 自动化管理入口

进入 `cd ~/Dev/jobs`。本目录是软链接工作台，配置与脚本保留在原项目；macOS 仍从 `~/Library/LaunchAgents` 加载任务。

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

| 入口 | 用途 |
|---|---|
| `launchagents/` | 当前用户的全部 launchd 配置，直接映射系统目录，新增任务自动可见 |
| `updates/` | 自动更新总入口与 Homebrew 维护脚本的链接；日常触发用 `ctl run always-latest` |
| `projects/mactools/` | 更新、周报/月报、到期提醒的实现 |
| `projects/dev-tools/` | Git 同步、健康检查、路径检查、下载整理等实现 |
| `projects/qinglong/` | 青龙签到与脚本调度；本机面板 http://127.0.0.1:5700 |
| `projects/notifhub/` | 通知采集、队列、总结与同步 |
| `projects/investment/` | 投资自动任务 |
| `projects/kb/` | 知识库导入与到期提醒 |

`ctl` 每次现场读取 `com.tianli.*`、`cyou.tianli.*`、`com.notifhub.*`，不维护第二份任务清单。第三方 LaunchAgents 可在 `launchagents/` 查看，但不纳入此命令的启停范围。青龙容器内任务、VPS 调度和第三方软件自带更新仍使用各自原管理入口；`qinglong-ckwatch` 只控制 Cookie 监视任务。

常用短名：`always-latest`（Homebrew 与 npm 全局更新）、`weekly-reports`、`monthly-reports`、`auto-git-sync`、`daily-health`、`paths-audit`、`downloads-router`、`qinglong-ckwatch`。通知任务可用完整名称，例如 `com.notifhub.summarize`。

排程以 plist 和任务代码的内部条件为准：`StartCalendarInterval` 用 Mac 本地时区，青龙用容器时区；每小时唤醒不等于每小时生成报告。已加载、进程退出码、实际业务成功是不同状态。

修改排程：在 `launchagents/` 找到对应 plist → 编辑前用 `ctl show` 确认其实际文件位置 → 修改 → `plutil -lint launchagents/<文件名>.plist` → `ctl reload <任务名>`。不要移动或删除链接指向的源文件。

重建此工作台：`python3 ~/Dev/tools/mactools/scripts/system/automation.py install`。安装只补齐链接，遇到同名的其他文件会报错，不覆盖用户内容，不变更任务状态。
