# mactools

> 📋 会话回顾：handoffs/sessions-recap.md（3 会话 merge,截至 2026-07-01;/start 从此接最新进度,源会话已退役）

macOS 日常效率工具集，从 scripts 仓库拆分。主要通过 Raycast 调用。

## 目录结构（2026-04-26 扁平化）

```
raycast/commands/   # 所有脚本 + Raycast 元数据头，扁平不分子类
lib/                # 公共库（display, file_ops, finder, clipboard, env, usage_log, llm_client, common.sh）
# venv 共享在 ~/Dev/.venv（uv workspace member · 见 ~/Dev/CLAUDE.md）
```

## 脚本清单（2026-07-27 按磁盘实测重写）

> 此前这一节列的 file/ system/ window/ 三组共 11 个脚本里,**5 个已在 `raycast/_archive/`**、
> **2 个(`display_1080.sh` / `display_4k.sh`)在任何位置都不存在**。清单以磁盘为准。

**`raycast/commands/`（在册,Raycast 扫描面）**
- `create_reminder.sh` — Apple 提醒事项创建
- `sys_app_launcher.py` — 按 `~/Desktop/essential_apps.txt` 启动应用
- `mem_hog.sh` — 内存占用大户(薄壳 → `bin/mem_hog.py`)

**`bin/`（命令行,不进 Raycast）**
- `brew_maintain.py` — Homebrew 全量维护
- `lid_sleep_toggle.sh` — 合盖不休眠开关
- `mem_hog.py` — 内存占用排行引擎

**`raycast/_archive/`（不装机;想恢复 mv 回 commands/）**
- `file_copy.py` · `file_print.py` · `folder_paste.sh` · `dingtalk_gov.sh` · `window_yabai.py`

> Downloads 整理三件套已迁出本仓 → `~/Dev/tools/dev/lib/tools/downloads_triage/`(挂 launchd
> `com.tianli.downloads-router`)。


- Shell: `source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"`
- Python: `sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib"))`
- LLM 调用: `from llm_client import chat`

## 开发约定

- 新脚本直接写到 `raycast/commands/`，头部加 `# @raycast.*` 元数据 + chmod +x
- 用 `pyyaml` 等依赖的 Python 用 `#!/Users/tianli/Dev/.venv/bin/python3` shebang（共享 uv workspace venv）
- 纯 stdlib 用 `#!/usr/bin/env python3`
- 公共库放 `lib/`，不要在 commands/ 下创建独立 lib
