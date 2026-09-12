# 周报与客户期限自动化

## 2026-09-12 周报改为北京时间周六早上8点

用户要求以后周六8点自动运行，并立即生成本期三类周报。`weekly_reports.py` 从本期起以 Asia/Shanghai 周六08:00为截止与到期时间，下一期为2026-09-19 08:00。首期窗口为2026-09-06 23:00至2026-09-12 08:00（北京时间），与上一期已发布窗口连续，旧归档不变。后续固定七天，不受美西夏令时变化影响；月报自然月和次月2日美西08:00规则不变。

保留已加载的 `com.tianli.reports` 每小时及加载时检查；当轮通过 `~/Dev/jobs/ctl run reports` 从真实调度入口启动。调度边界、下一期、休眠补最近期、首期衔接、采集日期与排除终点等周/月报相关32项测试通过。状态归档在 `~/Library/Application Support/WeeklyReports/2026-09-12/`，完成情况以各类 `state.json` 为准。

2026-09-08 调度入口已合并：周/月报使用 `com.tianli.reports`（每小时＋加载时），三类期限使用 `com.tianli.reminders`（本机每天 09:10＋加载时）。原业务脚本、状态与逐项通知保留；以下独立 label 仅为上线历史。当前控制与回退见 `../docs/automation.md`。

阅读修订：六篇周/月报与共享模板已扩充，正文来源编号改文末默认折叠；当前实现与取材上限以 /Users/tianli/Dev/tools/mactools/handoffs/report-reading-revision.md 为准。下文保留首期上线历史。

用户授权：每周投资总结、开发周报、水利周报；基于本人实际记录，生成后发布并通知。客户期限只读明确未完成记录，不猜日期或回款。

已实施：复用总部博客路径、生成、发布、私密阅读模板及 task_notify。三份周报周日 08:00 America/Los_Angeles，统计相邻两次周日 08:00 之间的记录；机器休眠后补最近一期，不补历史多期。com.tianli.weekly-reports 每小时检查，完成后静默；全局文件锁阻止并发。每期失败最多自动两次，至少间隔一小时；--retry 可人工恢复。

源：开发使用 /Users/tianli/Dev/tools/configs/repo-map.json 及总部 app_registry 枚举；水利使用 /Users/tianli/Work/projects/catalog.yaml 与 /Users/tianli/Work/shared/catalog.yaml。仅取本人提交者邮箱匹配记录，每仓最多最近16条，不把提交当成交付验收。投资使用逐日复盘。完整取材快照及日志在 /Users/tianli/Library/Application Support/WeeklyReports（私密权限）。模型按项目轮转最多96条/85000字符。无记录静默，有读取失败不得假报无工作。

客户扫描实测：4根、25份项目配置、1个合同库、27条交付记录，没有符合明确未完成状态的当前期限。已验收和状态不明的历史日期静默。com.tianli.client-due 每日系统时间09:10检查，提前14天开始；回款必须明确应收未付且依据文件存在。不会给客户发消息。

## 调用与恢复

- 执行：`bash /Users/tianli/Dev/tools/mactools/bin/weekly_reports.sh`
- 查窗口：`/Users/tianli/Dev/.venv/bin/python /Users/tianli/Dev/tools/mactools/bin/weekly_reports.py --check`
- 只取材：同命令 `--collect --kind development|water|investment`；已完成期拒绝覆盖。
- 恢复：shell入口 `--retry --kind water`；摘要/封面缓存复用，已发布不重新生成，通知失败只补通知。
- plist源在 /Users/tianli/Dev/tools/mactools/deploy，Library/LaunchAgents 为软链。
- 本机需登录并联网；休眠后补最近一期，不更改唤醒设置。

## 生成依赖

2026-09-06 实跑发现 Claude 返回 `Your account is on hold and can't use Claude Code`。总部 /Users/tianli/Dev/tools/dev/scripts/tools/llm_client.py 新增显式 `provider='codex'`，周报采用已登录Codex。其他调用默认不变；不固定模型、不新配API密钥。

每日投资 /Users/tianli/investment/options/robinhood/review_auto.py 的 --scheduled 同步改Codex；仅本次启用既有Robinhood MCP的8个只读get工具。最小生成与真实只读账户查询成功，未回填历史日报或修改真实账；未来目标日完整日报仍由原审计验收。

## 验证

调度/通知/客户过滤26项、总部Codex纯文本4项、每日生成器/调度16项测试通过。三份周报逐条对照原始记录，数字一致；封面与正文图目视检查无裁切。首期各阶段状态见 /Users/tianli/Library/Application Support/WeeklyReports/2026-09-06/*/state.json。

私密阅读总目录：https://tianli.cyou/private/blog/ 。

## 首期验收结果

2026-09-06 三份首期已完成真实生成、发布、源站正文/封面核验与通知发送。每个 kind 的 complete/notified 均为true。开发与水利的匿名边缘访问保护已核验，投资同样通过保护检查；未实际操作系统通知横幅点击，点击分支已有自动化测试，通知工具实际发送成功。

- 开发：https://blog.tianli.cyou/private-view/weekly-development-2026-09-06
- 水利：https://blog.tianli.cyou/private-view/weekly-water-2026-09-06
- 投资：https://blog-options.tianli.cyou/private-view/weekly-investment-2026-09-06

投资两图直接消费现有scoreboard的TWR/QQQ逐日收益与结算后buffer，所用5行字段快照在该文图片目录weekly-scoreboard.json；独立核验与原账本完全一致。下一期周报2026-09-13 08:00 PT；每日投资下一次触发2026-09-08 14:00 PT（Labor Day休市后）。两条新LaunchAgent已加载，实跑退出0。
