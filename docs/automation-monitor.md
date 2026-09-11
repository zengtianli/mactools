# 自动化菜单栏

Mac 菜单栏的“自动化”常驻显示正在运行的任务数；投资复盘运行时显示内容步骤计数，例如“复盘 5/7”。点击可查看任务步骤、用时、交易日、结果、异常和近期动态。每 5 秒刷新，数据留在本机。

弹窗按当前屏幕可用高度设置尺寸，标题、搜索、筛选和更新时间固定，任务详情在中部滚动。每次展开重新计算尺寸并取得焦点，避免窗口顶部被裁切。运行回执在应用内独立窗口显示概览、最近 200 行日志及原始回执；窗口跟随最新采集状态更新，也可在 Finder 查看原文件。

- 投资复盘读取 InvestmentDaily 回执和 `@@STEP@@` 审计进度；7/7 表示内容件齐全，“已发布并核验”另由外层发布回执确认。
- 周/月报和到期提醒显示分项回执；软件更新显示当前 Homebrew/npm 阶段。其他任务显示 launchd 进程状态，不将退出码 0 写成业务发布成功。
- 任务卡片展开后可设置：启动/进度/结束、仅结束与异常、仅异常、只在菜单栏显示。设置即时保存，重启继续生效。
- 默认投资复盘、报告、到期提醒、软件更新提醒关键变化；高频轮询及常驻服务只报异常，周/月报的快速空检查不弹通知。连续进度变化 30 秒内合并提醒；失败与完成不受此限制。
- 通知沿用 `bin/task_notify.py`，点击打开菜单栏应用；不自动抢焦点。发布任务原有正文通知保留。
- 收集器中断时保留上次状态并显示断线，不将旧缓存显示为当前成功。菜单应用由 launchd 常驻，采集器作为其子进程运行。

实现入口：`scripts/system/automation_monitor.py`；菜单 UI：`scripts/system/automation_menu/main.swift`。这是本模块内部功能，沿用原业务作业与排程。

```bash
cd /Users/tianli/Dev/tools/dev/lib/tools/macos
bash scripts/system/automation_menu/build.sh
python3 scripts/system/automation_monitor.py --install
python3 scripts/system/automation_monitor.py --once
```

程序位于 `build/Automation Monitor.app`，配置原版为 `deploy/com.tianli.automation-monitor.plist`。使用 `~/Dev/jobs/ctl show|pause|resume automation-monitor` 管理常驻状态。暂停监控只停止显示和新增进度通知，业务任务仍按原排程执行。

状态与提醒偏好：`~/Library/Application Support/AutomationMonitor/`。近期动态只保留最近 14 天、最多 200 条；任务原日志与业务回执不改。API 只监听 `127.0.0.1:8798`，无业务运行、暂停、发布接口；通知偏好写入要求同源。

验收：运行 `python3 -m unittest discover -s scripts/system -p test_automation_monitor.py`；用最终 App 的 `--check-json <真实API快照>` 核对 Swift 解码，并在菜单栏点开真实任务核验步骤、设置与刷新。
