---
dir: /Users/tianli/Dev/tools/mactools
n_sessions: 1
generated: 2026-06-26
sids: [cef4799f-5177-43b8-86fc-e15981916ede]
---

# mactools · 会话回顾（1 个会话）

本目录单次会话源于一段 Homebrew 后台维护输出里反复出现的 `Skipping X: most recent version Y not installed` 与第三方 tap `topit.rb` 的 `depends_on macos:` 弃用告警。会话从「实测核对真实状态」入手，定位根因为 macOS 27 被 brew 视为非 Tier-1 配置、后台维护开头 `brew update` 偶发拉取不全导致该升的没升，手动全量升级 7 个包消除告警，并给维护脚本 `bin/brew_maintain.py` 加了一道 cleanup 前的补升保险使该类告警结构上不再复发，已 commit+push（`70ccbba`）。

## brew 维护 Skipping 告警根治
- **起因**：用户在后台 brew 维护输出里反复看到 `Skipping libass/node@24/pyenv/ruff: most recent version not installed` 及 `topit.rb` 的 `depends_on macos:` 弃用告警，虽然末尾显示 `✅ 维护完成`，但仍贴出问「遇到这个问题，怎么解决」。维护其实成功，告警非错误。
- **迭代经过**：① 不凭记忆，先 `brew outdated` 实测发现矛盾（报不过时但 cleanup 说最新版没装）→ 判断本地 formula DB stale；② `brew update` 拉最新定义后确认这 4 个确实过时，根因=维护脚本跑 upgrade 时 DB 还旧；③ 升完又冒出 libarchive，识别为「打地鼠」→ 讲清 keg-only 依赖 + cleanup 每次只报第一个未升项的机制；④ 全量 upgrade 清空队列，cleanup 完全干净；⑤ 被 no-punt-guard hook 拦（结尾问「要不要加保险」=踢皮球）→ 直接动手给脚本加补升 step。
- **产出**：手动全量升级 7 个包 `libass/node@24/pyenv/ruff/libarchive/claude/typora`；给 `bin/brew_maintain.py` 在 cleanup 前加补升保险（核对 `brew outdated --formula --quiet` 残留并补 `brew upgrade`）；commit+push `70ccbba`；`brew cleanup` 跑 3 次均干净无 Skipping。
- **关键决策 / 用户原话**：用户「遇到这个问题，怎么解决」；被 hook 拦后「直接做完那件事，做完再 stop，别问」；用户追问「你验证完 没问题了吗」。决策：topit.rb 弃用告警来自第三方 tap，Homebrew 自己都说别报给它、忽略等作者修，不改本地 cask（会被 tap 更新覆盖）。
- **未尽事项**：完整 `brew_maintain.py --auto` 未实跑（会自动卸载孤儿 cask，破坏性，不盲跑），仅原样抽出新增 5.5 段代码实跑验证逻辑分支；5.5 里 `brew upgrade` 那一刀因当前 `leftover=0` 未被实际触发（但与 line 66 已验证的同条命令一致）；`topit.rb` 弃用告警无法修，下次维护仍会刷，属正常。
- **sid**：`cef4799f-5177-43b8-86fc-e15981916ede`
