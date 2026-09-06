# 月报自动化

用户要求开发、水利、投资三类月报，并授权选择合适起始时间。

选择：先补2026-08完整自然月；每月2日08:00 America/Los_Angeles生成上月，给月末结算/补记留一天。沿用私密博客、直达正文通知及现有周报引擎，状态独立。

取材核验：开发526条、水利275条记录沿整月采样；投资daily-review共21篇，与交易日历对账通过。scoreboard原缺8月3日，已用既有day_vs_qqq.row同源逐日收益补齐；8月3日缓冲仍缺测并留空。完整21日复合TWR为6.75810391249323%，QQQ为4.183201006725712%，差2.5749029057675177pp；不使用7月9日起跨月累计。审计资料在 /Users/tianli/Library/Application Support/WeeklyReports/monthly/start-audit，逐日报告与公式在投资月报图片目录的monthly-scoreboard.json。

实现：复用weekly_reports.py/weekly_render.py，--frequency monthly；手动补期--period YYYY-MM（必须完整过去月）。状态独立保存在WeeklyReports/monthly/YYYY-MM，沿用全局发布锁、私密博客、来源归档、封面及直达正文通知。每仓沿全月均匀选取最多40条，摘要按项目/周段轮转最多160条。月收益必须通过完整交易日集合及数值校验后逐日复合。

定时：deploy/com.tianli.monthly-reports.plist已软链到~/Library/LaunchAgents并bootstrap；每小时检查最新到期月份，按America/Los_Angeles计算每月2日08:00，开机补跑，不重复成功期。首次启动exit 0。下一期2026-09于2026-10-02 08:00美西时间到期。日志~/Library/Logs/monthly-reports.{log,err}权限0600。

验证：37项单元检查通过（含跨月/DST、完整日历、+10%后-10%=-1%、缺日/重复/无效收益拒绝月总值）。首期三张封面和六张图已目视检查；投资事实与21日合成结果另经只读核验。总部能力登记已提交3b8d475并推送，module-map已刷新。

首期发布/通知验收：三类2026-08月报均已发布并发送直达正文通知，各kind/state.json的complete与notified均为true。地址为https://blog.tianli.cyou/private-view/monthly-development-2026-08、https://blog.tianli.cyou/private-view/monthly-water-2026-08、https://blog-options.tianli.cyou/private-view/monthly-investment-2026-08。生产链核验线上私密正文/封面及匿名访问保护，私密目录已同步；通知CLI成功，未声称实机点按横幅视觉验收。文章与各自图片已由既有backup_post按明确路径提交并推送。
