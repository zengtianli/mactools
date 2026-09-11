# 自动更新与通知改造

## 2026-09-11 菜单栏修复与 govern

本会话新增的 Automation Monitor 原来只核了状态JSON，漏掉真实弹窗裁切/焦点与回执按钮可用性。已修 `scripts/system/automation_menu/main.swift`：打开时设置 hosting 和 popover 的明确尺寸、按所在屏幕可用高度限制并取焦点；回执打开应用内概览/日志/原始回执窗口，跟随采集更新，长日志只呈现最近200行。已装机 CUA 实测搜索、筛选、展开、滚动、提醒保存与恢复、回执读取及结果打开实际博客正文。不能把 getApp 激活、AX 树存在或 NSWorkspace.open 的返回值作为所有交互通过。当前提醒保留启动/进度/结束。

源提交 `6225ce9` 已推送；之前大日志进度、后端恢复、通知去重和服务/作业分辨已在原实现修复。本轮8项状态回归通过，真实API19项任务由最终Swift产物解码通过。操作细节仍只在 `docs/automation-monitor.md`；通用菜单栏验收已回流 app 技能原版。全量错误责任与验证索引见 `/Users/tianli/investment/options/handoffs/daily-review-automation.md` 的同日 govern 节；没有新增第二套通知服务或治理台账。

用户授权：保留实用自动更新，失败才通知；点击看完整结果；期限逐项去重和稍后提醒；TestFlight 只检查到期、不自动构建上传。

## 已落地

- `bin/task_notify.py` 统一复用已安装 terminal-notifier；点击打开本地 TextEdit 详情与提醒选项。发送失败不记录成功，状态文件0600，跨源共享锁。
- `bin/due_notify.py` 消费原学术/案件检查器；每项单独通知，不截前三项。相同事件7天内去重，支持暂停24小时后下一次检查提醒、本轮不再提醒；不修改业务台账。
- 学术入口 `/Users/tianli/Dev/tools/kb/bin/acad_due_notify.sh` 与案件入口 `/Users/tianli/Archives/ip-legal/.tools/cases_due_notify.sh` 统一消费总部。
- 案件源已写明“已交邮（口述）”时，通知显示待核底单/回执，不再笼统报逾期；原始参考日期保留。
- `/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/testflight-expiry-cron.sh` 只检查；实际检查全部应用距过期至少14天。
- 青龙现有本地/手机通知各自记录发送成功，12小时去重，恢复清理，手机点开已有战果页。本机通知只打开处理步骤，不自动重登。
- `bin/always_latest.py` 已装入原每周一11:00 LaunchAgent；修复 scoped npm `.DS_Store`、失败传播与汇总。
- terminal-notifier 已在系统通知设置启用，关闭其自动摘要；诊断 authorization=authorized，通知列表实际包含验证通知。

## 验收与状态

- 共享通知去重、发送拒绝、暂缓、不再提醒、新事件重置已通过真实函数替身测试。
- 案件/学术 dry-run 已运行：当前案件1项待核回执，学术0项。
- 真实软件升级已结束（20260906-074340.log，exit 1 如实保留部分失败）：formula 3项及 ChatGPT/Stats/腾讯会议/字体完成，gstreamer 检查返回0；npm 完成（新增154、移除711、变更372包），@google/.DS_Store 已可恢复归档。钉钉与 Java（Temurin）需管理员密码，未重试；同一通知组已更新为2项需处理及完整原因，发送exit0。
- 真实发送、通知列表送达记录、相同案件的第二次运行去重均已验证；生产 `--interact` 与 `--action open` 详情处理路径实际退出0。尚未完成亲手点横幅的端到端 UI 验收：CUA 在软件更新过程中出现 `Sky Computer Use native pipe startup failed`，重置后仍失败。没有把命令成功当作完整 UI 点击验收。
- 5项共享通知回归测试通过；案件口述已交邮/未递交/已完成三个对照通过。TestFlight真实检查全绿、没有触发构建上传。
- 所有相关代码已分别提交推送到 mactools、devtools、personal-kb、ip-legal、qinglong；原8项后台触发器保持停用，5个保留入口均已加载。
- module-map 已从 catalog 重建到 `~/Library/Application Support/AutomationUpdates/module-map.json`，83个包、177条边；共享入口已登记总部 `hq_capabilities.yaml`。

运行状态：`~/Library/Application Support/TaskNotifications/`；更新日志：`~/Library/Application Support/AutomationUpdates/`。
前轮停用的8项后台触发器继续禁用；配置归档见 `~/Library/Application Support/AutomationArchive/20260906-064836/`。
