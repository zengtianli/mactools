# 目录归位 · 2026-09-08

用户要求青龙尽量收进 jobs，并检查全局错位目录、迁移并对齐 SSOT。

## 已迁移

| 原位置 | 当前真身 | 依据 |
|---|---|---|
| `~/Apps/cli/qinglong` | `~/Dev/jobs/qinglong` | 用户明确按个人自动化作业管理 |
| `~/Dev/apps/infra/downloads-organizer` | `~/Apps/mac/downloads-organizer` | pyproject 入口为独立桌面 GUI，自带依赖；不是总部管线 |
| `~/Dev/apps/ai-tools/cc-dispatch` | `~/Apps/_archive/cc-dispatch` | catalog 已声明 archived，完成物理归档 |
| `~/Dev/apps/lewislulu-html-ppt-skill` | `~/Dev/tools/html-ppt-skill` | 只读主题/模板技能素材库，deck_build 消费它；不是应用 |

青龙旧 `jobs/projects/qinglong` 别名已移除；项目、容器数据和 `deploy/com.tianli.qinglong-ckwatch.plist` 原版均在新真身。系统 LaunchAgents 链接到该 plist。其他业务仓通过 jobs/projects 接入，原目录保持归属，未复制业务状态。

## 扫描范围与判断

独立枚举 Apps、Dev/apps、Dev/services、Dev/jobs、Dev/tools、Work、Money、Edu、VPS、School、Ghostwriting、Relations、investment 的项目标记（最多三层，排除依赖、数据、构建与历史子树）；另用现成注册表扫描所有在册根，共 171 份 catalog。Apps 物理分类下 59 个项目 catalog 全部与 home_of 一致。系统与第三方应用自建数据目录、客户项目内部布局不按名称猜测迁移。

通知中心仍是独立应用；投资、报告、提醒保留原业务实现；LLM 内容生产与演示管线保留 Dev/apps/ai-tools。各类历史 .MOVED-TO 空壳不当作活项目误搬。未声称扫描整个磁盘、所有 ignored 数据或 VPS 文件树。

## SSOT 与消费者

- paths.yaml 登记绝对路径和 ~/ 写法，并将相关旧迁移目标直接指向最终位置；build-const 已刷新。
- 青龙容器用新目录 compose 重建，沿用原镜像、DNS、仅本机端口；旧容器在核验后移除。
- app_registry 增加 jobs 真身扫描，排除工作台链接集合和回退记录；repo_map_gen 增加 jobs 并排除 symlink 别名。
- harness.yaml、青龙技能原版、Codex 入口、deck_build、web_login 手机号位置、部署与产品登记、站群说明书生成器、jobs 安装器与 HTML 已同步。
- 按现场合并结果修正 reports/reminders/downloads-router 的 catalog 声明，撤掉已退役 acad-due/cases-due/client-due/weekly-reports/monthly-reports/optionsdesk-close；业务脚本和排程未改。
- apps 两个管线分组 catalog 纳入 Dev 元仓版本管理，子项目仍由各自仓库管理。
- 原记忆 namespace 保留，home 记忆索引标明青龙新入口；不复制历史会话。

## 验证

- 青龙迁移前后 60 个任务、49 个启用项；API 比对 id/name/command/isDisabled/schedule 完全相同。本机 jdpro 启用 48，smzdm 不在本机启用。
- 镜像 ID、DNS、端口绑定均不变；挂载确认 `/Users/tianli/Dev/jobs/qinglong/data`。
- `ctl show qinglong-ckwatch` 确认新脚本/日志/真实 plist 路径；迁移后实际运行退出 0。全部任务 17 项，12 已加载、5 暂停，保留原状态。
- downloads-organizer 用新路径重建虚拟环境，22 项测试通过。
- 青龙内部 douyin-mcp 已有虚拟环境的入口、editable .pth 和 direct_url 路径已同步；解释器导入路径验证通过，未启用 MCP。
- 注册表 171 份 catalog，enumeration_errors 和 local_errors 均为空；Apps 59 项落位一致。
- paths audit --strict 退出 0；菜单 audit 结构及线上保护检查通过；说明书生成器 --check 通过。未发布网站。
- 站群完整 `pnpm build` 在依赖解析阶段受已有 `@tlz/i18n@workspace:*` 缺少 workspace 包的问题阻断；本次仅验证说明书生成一致性，没有声称整站构建或上线通过。
- CK 写回验活改用原 ck_probe 的复检接口；模拟首探误报随后恢复、复检仍失效两种结果通过；登录日志不再打印手机号、短信验证码或 CK 前缀。

## CK 尚未完成

新路径现场复检两次仍 DEAD。已运行 `qinglong/auto-login/relogin.sh`，自动填号、勾选和点击发码代码已执行，但截图仍是登录表单。该进程等待 900 秒未收到验证码，最终退出 3，未取得新 CK。不能把旧日志打印的“验证码已弹出”当成验证码确已显示；源码措辞已修正。已询问用户能否看到专用京东登录窗口，尚待回复。后续先确认窗口与发码响应；若用户已完成登录，先核 result.json 时间，再由 set_ck 验活，避免无谓再次发码。

## 回退依据

本轮涉及的 15 个仓库提交均已推送，核对 HEAD 与各自 upstream 无领先/落后。提交快照在下方回退目录 `commits.json`。保留用户原有未提交差异（青龙历史账本、Apps 推广材料、站群既有生成差异、下载工具 Raycast 注释等），未一并提交。

`~/Dev/jobs/archive/placement-20260908-223923/` 保留映射、独立枚举结果、迁移前任务定义、容器配置、数据库备份、旧 LaunchAgent 与并发 diff；目录权限 0700，不入 git。路径重写前件在 `~/Dev/_archive/path-rewrites/20260908-224307/`。

回退需同时处理目录与消费者：先 bootout 青龙监视器并在新目录 compose down；将四个真身按 mappings.jsonl 反向迁回；还原本次路径及登记变更、恢复旧 plist 和工作台链接；旧位置 compose up -d --pull never，再 bootstrap 监视器并比对 crons-before.json。保留当前活数据；只有明确需要恢复数据库且确认会覆盖新状态时才使用 db-before。旧容器已删除，不依赖它回退。
