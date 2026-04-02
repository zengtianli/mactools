# mactools

macOS 日常效率工具集，从 scripts 仓库拆分。主要通过 Raycast 调用。

## 目录结构

```
scripts/
├── file/      # 文件操作
├── system/    # 系统工具
└── window/    # 窗口管理

lib/           # 公共库（display, file_ops, finder, clipboard, env, usage_log, llm_client）
raycast/       # Raycast 入口
├── commands/  # Shell wrapper
└── lib/       # 运行器 (run_python.sh)
```

## 脚本分类

### file/ - 文件操作
- `downloads_organizer.py` - Downloads 按扩展名自动分类
- `smart_rename.py` - AI 驱动的文件重命名（依赖 lib/llm_client）
- `file_copy.py` - Finder 选中文件复制
- `file_print.py` - Finder 选中文件打印
- `folder_paste.sh` - 粘贴板文件粘贴到当前目录

### system/ - 系统工具
- `sys_app_launcher.py` - 应用启动器
- `display_1080.sh` / `display_4k.sh` - 显示器分辨率切换
- `dingtalk_gov.sh` - 政务钉钉启动
- `create_reminder.sh` - Apple 提醒事项创建

### window/ - 窗口管理
- `yabai.py` - Yabai 窗口管理统一工具

## 引用路径

- Shell: `source "$(dirname "$0")/../../lib/common.sh"`
- Python (scripts/): `sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "lib"))`
- LLM 调用: `from llm_client import chat`

## 开发约定

- Raycast wrapper 在 `raycast/commands/`，通过 `run_python.sh` 调用
- 公共库在 `lib/`，不要在脚本目录下创建独立 lib
