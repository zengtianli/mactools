# 自动更新与通知改造

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
- 真实软件升级正在执行，最终结果待本轮回填。
- 真实通知点击的 UI 验收进行中；不能以发送回执替代点击验证。

运行状态：`~/Library/Application Support/TaskNotifications/`；更新日志：`~/Library/Application Support/AutomationUpdates/`。
前轮停用的8项后台触发器继续禁用；配置归档见 `~/Library/Application Support/AutomationArchive/20260906-064836/`。
