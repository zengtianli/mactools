# jobs 交接 · 2026-09-08

> 后续目录归位已完成：青龙真身在 `~/Dev/jobs/qinglong`，另外三项目录归位和全局 SSOT 对账见 [placement-20260908.md](placement-20260908.md)。CK 新路径复检仍失效，重登尚未取得新 CK；先接该记录，不按下方较早的软链接方案搬回。

## 用户目标与已完成

用户要把自动化放在一个可 `cd` 进入的目录，接受用软链接集中管理；要求 HTML 展示，并已授权落实合并建议和软件更新时弹出管理员密码输入框。

工作台位于 `/Users/tianli/Dev/jobs`。`ctl`、配置目录、更新脚本、业务仓库和说明已链接到原位置；`index.html` 已生成并在 Chrome 检查搜索、排序、证据展开和复制命令。最新计数是现场快照：17 个个人 launchd 配置，12 已加载、5 已暂停；后续以 `./ctl list` 为准。

## 合并结果

- `weekly-reports`＋`monthly-reports` → `reports`：每小时整点和加载时检查。
- `acad-due`＋`cases-due`＋`client-due` → `reminders`：本机每天 09:10 和加载时检查。
- 已暂停的 `optionsdesk-close` 退出活目录，原部署源移到 investment 的 `deploy/retired/`；现行投资每日复盘未改。
- 原业务脚本、窗口、重试、日志、通知去重保留；其他任务没有恢复或更改排程。

迁移前六份配置、原启停/加载状态及回退脚本：`/Users/tianli/Dev/jobs/archive/consolidation-20260908-200803/`。`restore.py --check` 已只读验证，未执行回退。旧部署源在原项目 `deploy/retired/`，不要批量装回。

验证：两个新 LaunchAgents 的首次真实运行均退出 0，五个子任务全部退出 0；原报告 `state.json` 哈希不变，没有重新生成或重发已完成报告。分项失败、超时、缺失命令后的继续执行与日志隔离测试通过；原周报/客户判定测试 26 项通过。HTML 已检查 1440/900/500 宽度。

## 软件更新授权

`always_latest.py` 调 `brew_maintain.py --auto --gui-sudo`，通过本机 Homebrew 已有的 `SUDO_ASKPASS` 支持，使用 `scripts/system/update_askpass.py` 显示隐藏密码框。用户已接受此方式。密码不落盘；临时目录仅含取消标记。取消或 120 秒未响应后，本轮后续 sudo 不再弹窗；下次运行可再授权。缓存遵循 sudo 原策略，可能跨软件或超时后再弹，不提供 Touch ID。

真实 `sudo -A -k /usr/bin/true` 通路测试返回成功；测试只验证身份，没有执行全量软件升级。四项测试覆盖秘密仅经 stdout 管道返回、取消防重复、超时不泄露输出、环境与临时目录清理。**尚未声称钉钉、Temurin 等待更新软件已经升级成功**；如用户要求现在更新，走 `./ctl run always-latest` 并核对应日志与安装版本。

## 已提交与下一步

相关源码已提交推送：mactools `e3b3dbd`（授权弹窗），此前 `94722f4`（分组调度）；investment `86c52a4`（旧触发归档）；cc-home `97973e9`（reports 技能指向新调度），技能分发两端已对齐。本次 jobs 项目上下文与交接另由同仓提交保留。

当前没有待修复阻断。用户正在切到 jobs 工作；后续按新请求处理，不自动触发全量维护。项目上下文见上级 `CLAUDE.md`，使用方法见 `~/Dev/jobs/README.md`。
