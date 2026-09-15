# 资源监控 · 2026-09-15

用户要求：持续记录高负载、分析原因和修复选项；安全且可确认的自有残留子进程自动清理，不确定的应用退出由本人决定；一键勾选推荐项后直接关闭已选。保护现有终端任务。解释要帮助用户理解、复述和应对面试。

## 当前实现

原版在 `scripts/system/resource_watch/`，安装 App 在本模块 `build/Resource Watch.app`。launchd 入口为用户 `~/Library/LaunchAgents/com.tianli.resource-watch.plist`，链接本仓 `deploy/` 原版；不是 `/Library/LaunchDaemons/`。本轮保留 plist 与 config 的已有并发修改，只 build-only 并通过 jobs/ctl 重载监控本身。

- 15 秒采样；整机 CPU、PID/微秒启动身份、CPU/RSS 独立榜、终端父链、内存压力、交换存量与换页速率、压缩内存、热压力和屏幕信息。自身命令 3 秒超时，回收自建进程组，不杀用户进程。
- 事件记录：CPU 90%/60秒、75%/120秒、WindowServer 150%单核/120秒、同实例95%单核/180秒、warning+CPU/换页/180秒、critical/45秒等独立窗口，80%命中容忍；断档重置。warning但CPU/换页已低可结案，unknown不据称恢复。
- 9月15日下午按用户纠正收紧自动弹窗：仅整机 CPU≥95% 连续60秒（15秒采样）才可触发。低于95、无效值或漏采重置；其他异常仅留证，主动查看仍可。独立配置 `prompt_cpu_threshold=95`、`prompt_sustained_seconds=60`，避免旧记录阈值90%影响打扰门槛。已构建并重新加载，策略75项、全套225项通过。
- 每事件保留告警前、首次、峰值、时间线、恢复及中文事实/推断/建议/原理。首次后台限量采最多两个同用户进程堆栈，权限不足明确记录，不提权、不停止被采样进程。
- 菜单栏“负载”保留入口。120秒提示收起后仍能查事件；记录启动、已呈现、失败、取消、超时、推荐勾选、退出请求与观察结果。正常30分钟冷却和失败30秒重试分离，严重度升级可提前提醒。
- “一键勾选推荐项”按CPU或内存选择最多3个合格普通应用，附数值依据；过期/身份不确定/终端/系统/网络/文稿或代码编辑器不自动勾选。没有合格项就不推荐。
- 用户点“关闭已选”即发正常退出请求，保留应用自己的保存/拒绝流程，不再重复确认。可手选本用户输入法原实例、明确图谱任务暂停；未知非GUI后台程序仅诊断。所有动作核对原始微秒身份、UID、路径、当前父链与60秒新鲜度，过期可刷新。
- 自动“清理”只涉及监控自己创建的超时子进程和到期日志。高CPU/PPID=1不证明卡死；僵尸已不执行，不能重复kill。没有自动删除应用、业务文件或强杀用户程序的功能。

## 验证

`python3 scripts/system/resource_watch/tests/run.py`：202项通过（采样44、策略52、事件保存13、堆栈诊断32、动作/推荐及隔离App61）。覆盖不影响无关进程的超时清理、PID复用、终端保护、告警冷却升级、内存恢复、事件重启/峰值保留及推荐过滤。

隔离测试App实测正常退出和拒绝退出；自有sleep实测采样后同一实例继续运行。旧真实历史片段回放新策略比旧规则提前135秒提示，仅证明所选片段。没有人为制造整机过载或关闭用户App验收。

已安装二进制经 launchd 运行并连续写入新字段，版本 `2026-09-15-incidents-v2`。真实一次采样约75–160ms（随负载变化）；服务现场 ps CPU 0.0%、RSS约39MB，非长期峰值保证。

同一安装二进制在隔离预览包通过 CUA 核对长清单、CPU/内存解释、推荐按钮与终端禁选；实际点击“一键勾选推荐项”勾选1项，再预览确认，actions留下 preview_confirmed/preview_closed，用户Dia及Ghostty仍在运行。已验证120秒超时事件。直接附着多实例同bundle的安装App曾CUA超时，改用相同二进制唯一bundle预览；不把该工具超时当成程序未运行。

## 记录与维护

本地 `~/Library/Application Support/ResourceWatch/`：原始采样14天；`incidents/`事件与堆栈90天；`latest-advice.{json,md}`当前建议；`actions.jsonl`处理结果；配置和提示冷却另存。日志不离机，不进入Git。读取堆栈仍需结合任务进展验证，规则分析不会自动证明根因。

构建安装：`python3 scripts/system/resource_watch/install.py --build-only`；重载：`~/Dev/jobs/ctl reload resource-watch`；只读诊断：已安装二进制 `--diagnose 2`。完整配置/边界见实现 README。

9/14原始复盘见 [resource-incident-20260914-review.md](resource-incident-20260914-review.md)。本轮修复承接该复盘，不把后续能力补写成事发时已存在。教学协作偏好写入全局唯一源 `~/Dev/tools/cc-home/HARNESS.md` 并经 codex_sync 分发；不把资源阈值放进全局规则。
