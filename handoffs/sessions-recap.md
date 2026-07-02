---
dir: /Users/tianli/Dev/tools/mactools
n_sessions: 3
generated: 2026-07-01
sids: [cef4799f-5177-43b8-86fc-e15981916ede, 7a407a41-9bf8-4b6f-9b93-fc0aff06e52d, 1c5a1975-eb16-4405-a719-7e2a210af381]
---

# mactools · 会话回顾（3 个会话 · 截至 2026-07-01）

本目录三个会话围绕两条主线：**Homebrew 维护线**（2 会话）从后台维护输出的 `Skipping X` 告警根治（给 `bin/brew_maintain.py` 加 cleanup 前补升保险，commit `70ccbba`）延伸到全量装机盘点——按 cask 最后使用日期 + 体量给出红黄绿删留清单，实际卸载 VSCode 省回 ~780M，并明确 formula 用量信号弱不可作删除依据、libreoffice/basictex 等「无启动日期基础设施」不可删；**系统急救线**（1 会话）修复 macOS 27 开机后通知栏消失：根因为 yabai 旧 SA 在 macOS 27 beta 打坏窗口层致 `NotificationCenter` 进程卡死，禁用 SA 注入拔根因 + `killall NotificationCenter` 重生进程，截屏实证渲染恢复，并沉淀出菜单栏区域四进程 killall 急救速查表。

## brew 维护 Skipping 告警根治
- **起因**：用户在后台 brew 维护输出里反复看到 `Skipping libass/node@24/pyenv/ruff: most recent version not installed` 及 `topit.rb` 的 `depends_on macos:` 弃用告警，虽然末尾显示 `✅ 维护完成`，但仍贴出问「遇到这个问题，怎么解决」。维护其实成功，告警非错误。
- **迭代经过**：① 不凭记忆，先 `brew outdated` 实测发现矛盾（报不过时但 cleanup 说最新版没装）→ 判断本地 formula DB stale；② `brew update` 拉最新定义后确认这 4 个确实过时，根因=维护脚本跑 upgrade 时 DB 还旧；③ 升完又冒出 libarchive，识别为「打地鼠」→ 讲清 keg-only 依赖 + cleanup 每次只报第一个未升项的机制；④ 全量 upgrade 清空队列，cleanup 完全干净；⑤ 被 no-punt-guard hook 拦（结尾问「要不要加保险」=踢皮球）→ 直接动手给脚本加补升 step。
- **产出**：手动全量升级 7 个包 `libass/node@24/pyenv/ruff/libarchive/claude/typora`；给 `bin/brew_maintain.py` 在 cleanup 前加补升保险（核对 `brew outdated --formula --quiet` 残留并补 `brew upgrade`）；commit+push `70ccbba`；`brew cleanup` 跑 3 次均干净无 Skipping。
- **关键决策 / 用户原话**：用户「遇到这个问题，怎么解决」；被 hook 拦后「直接做完那件事，做完再 stop，别问」；用户追问「你验证完 没问题了吗」。决策：topit.rb 弃用告警来自第三方 tap，Homebrew 自己都说别报给它、忽略等作者修，不改本地 cask（会被 tap 更新覆盖）。
- **未尽事项**：完整 `brew_maintain.py --auto` 未实跑（会自动卸载孤儿 cask，破坏性，不盲跑），仅原样抽出新增 5.5 段代码实跑验证逻辑分支；5.5 里 `brew upgrade` 那一刀因当前 `leftover=0` 未被实际触发（但与 line 66 已验证的同条命令一致）；`topit.rb` 弃用告警无法修，下次维护仍会刷，属正常。
- **sid**：`cef4799f-5177-43b8-86fc-e15981916ede`

## Homebrew 装机盘点 + VSCode 卸载（2026-06-28）

- **一句话主题**：以 cask 最后使用日期 + 实际体量为信号做全量 Homebrew 包删留裁决，实际卸载 VSCode 省回 ~780M。
- **起因**：用户贴出 `uv run python3 bin/brew_maintain.py` 的维护输出，顺势要求盘点已装包哪些还在用、哪些可清。
- **迭代经过**：① 采集数据后明确「CLI formula 与 GUI cask 信号强度不同，分开看」；② cask 按最后启动日期 + `/Applications` 体量排出红黄绿三档：🔴 visual-studio-code（26 天未用+本次升级失败）/ upscayl（761M 从未启动）/ wine-stable（666M 半年未用且与 CrossOver 重叠），🟡 chatgpt / iterm2（已转 ghostty）/ mathpix / zotero / figma 等建议或看用户，🟢 feishu（1.3G 但工作 IM）/ tencent-meeting 由用户定；③ 显式圈出「别被体量骗删」项：libreoffice（`/docx` `/img` skill 靠 soffice 高频后台调用）、basictex/temurin/gstreamer-runtime（quarto/drawio/plantuml 运行时依赖）、字体类——无「打开」记录但是基础设施；④ 指出 ~110 个显式 formula 的用量统计基本不可信（工具藏在脚本/skill 里被间接调用），不按此删；⑤ 用户拍板卸 VSCode → `brew uninstall --cask visual-studio-code` 执行并验证。
- **产出**：VSCode 彻底卸载（app 删除 + `code`/`code-tunnel` 命令链接撤除 + cask 列表核对无此项），省回 ~780M；一份全量 cask 红黄绿删留清单 + 「绝对别动」高频清单（claude/obsidian/typora/wechat/ghostty/chrome + stats/hammerspoon/topit 等菜单栏常驻）。
- **关键决策 / 用户原话**：用户直接下指令「brew uninstall --cask visual-studio-code」。决策：cask 最后使用日期是强信号、formula 用量是弱信号不可作删除依据；无启动日期的运行时依赖类一律留。
- **未尽事项**：🔴 档剩余 upscayl（761M 从未启动）和 wine-stable（666M 半年未用）用户未表态、未清；🟡 档（chatgpt/iterm2/mathpix/deckclip/zotero/figma）均待用户拍板。
- **sid**：`7a407a41-9bf8-4b6f-9b93-fc0aff06e52d`

## macOS 27 通知栏消失修复（2026-07-01）

- **一句话主题**：修复 macOS 27 开机一段时间后通知栏消失且调不出来的问题——根因是 yabai 旧 SA 打坏窗口层致 NotificationCenter 卡死，禁 SA + killall 重生解决。
- **起因**：用户报「macOS 27 开机后过一会通知栏会找不到、也调不出来」，问是不是 bug、怎么修。
- **迭代经过**：① 排查定位根因 = yabai 的旧 scripting-addition 在 macOS 27 beta 上打坏窗口层，禁用 SA 注入并提交；② 用户授权「全部都做了 自行决定 这些简单问题」后用户仍反馈「通知栏没有」→ 继续查：NotificationCenter 进程卡死（进程活着但绘制层坏了），`killall NotificationCenter` 让 launchd 重拉干净进程（813 → 14158）；③ 按铁律自行验证：确认 yabai 未托管任何通知中心窗口（排除遮挡）、截屏实证右侧正在弹通知横幅（渲染恢复）；AppleScript 点时钟触发撞辅助功能权限墙，「点击弹出」这最后一下留用户亲试；④ 用户确认「现在好了」并追问用了什么命令 → 给出原理讲解 + 速查表。
- **产出**：通知栏恢复正常（用户实测确认）；yabai SA 注入禁用已提交（根因拔除，不再周期性复发）；菜单栏区域急救速查表（NotificationCenter / ControlCenter / Dock / SystemUIServer 四进程 killall，均由 launchd 守护杀了必自动重启，可放心作标准急救）。
- **关键决策 / 用户原话**：用户「全部都做了 自行决定 这些简单问题」授权直接干；「好了，我说的 通知栏没有」纠偏指认症状未消；「现在好了，你是做了什么…教我」→ 转教学。决策：进程健康 + 正在渲染两条自证，点击手势因权限墙留给用户拍板，不虚报「点击已验证」。
- **未尽事项**：会话末尾提议把 `killall NotificationCenter` 包成 Raycast 命令「Fix Menubar」放进本仓库，未获回应、未实施。
- **sid**：`1c5a1975-eb16-4405-a719-7e2a210af381`

---

**sid 列表**：
- `cef4799f-5177-43b8-86fc-e15981916ede` — brew 维护 Skipping 告警根治（2026-06-26 前）
- `7a407a41-9bf8-4b6f-9b93-fc0aff06e52d` — Homebrew 装机盘点 + VSCode 卸载（2026-06-28）
- `1c5a1975-eb16-4405-a719-7e2a210af381` — macOS 27 通知栏消失修复（2026-07-01）
