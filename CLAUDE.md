# mactools

macOS 日常效率工具集，从 scripts 仓库拆分。主要通过 Raycast 调用。

## 目录结构（2026-04-26 扁平化）

```
raycast/commands/   # 所有脚本 + Raycast 元数据头，扁平不分子类
lib/                # 公共库（display, file_ops, finder, clipboard, env, usage_log, llm_client, common.sh）
.venv/              # uv 管理的依赖（pyyaml 等）
```

## 脚本清单

**file/**
- `downloads_organizer.py` - Downloads 按扩展名自动分类（venv shebang，需 yaml）
- `smart_rename.py` - AI 驱动的文件重命名（venv shebang，需 yaml）
- `file_copy.py` - Finder 选中文件复制路径/名称
- `file_print.py` - Finder 选中文件打印
- `folder_paste.sh` - 粘贴板文件粘贴到当前目录
- `file_cleanup-downloads.sh` - 三步编排：分类 → 重命名 → 归组

**system/**
- `sys_app_launcher.py` - 按 `~/Desktop/essential_apps.txt` 启动应用
- `brew_maintain.py` - Homebrew 全量维护
- `display_1080.sh` / `display_4k.sh` - 显示器分辨率切换
- `dingtalk_gov.sh` - 政务钉钉启动
- `create_reminder.sh` - Apple 提醒事项创建
- `sys_oa.sh` - 启动 OA Streamlit

**window/**
- `yabai.py` - Yabai 窗口管理（float/mouse/org/toggle 子命令）

## 引用路径（move 后仍有效，3 层深度未变）

- Shell: `source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"`
- Python: `sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib"))`
- LLM 调用: `from llm_client import chat`

## 开发约定

- 新脚本直接写到 `raycast/commands/`，头部加 `# @raycast.*` 元数据 + chmod +x
- 用 `pyyaml` 等依赖的 Python 用 `#!/Users/tianli/Dev/tools/mactools/.venv/bin/python3` shebang
- 纯 stdlib 用 `#!/usr/bin/env python3`
- 公共库放 `lib/`，不要在 commands/ 下创建独立 lib
