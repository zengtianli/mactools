# mactools

macOS 本机小工具。**目录结构以磁盘为准,下表 2026-07-27 按实测重写**
(此前列的 9 个脚本里 5 个已在 `raycast/_archive/`、2 个根本不存在)。

## 在册 Raycast 命令 (`raycast/commands/`)

| 脚本 | 功能 |
|------|------|
| `create_reminder.sh` | 创建 Apple 提醒事项 |
| `sys_app_launcher.py` | 应用启动器 |
| `mem_hog.sh` | 列内存占用大户(薄壳,引擎在 `bin/mem_hog.py`) |

## 命令行工具 (`bin/`)

| 脚本 | 功能 |
|------|------|
| `brew_maintain.py` | Homebrew 维护(update/upgrade/cleanup/doctor) |
| `lid_sleep_toggle.sh` | 合盖不休眠开关 |
| `mem_hog.py` | 内存占用排行引擎 |

## 已归档 (`raycast/_archive/`,不装机)

`file_copy.py` · `file_print.py` · `folder_paste.sh` · `dingtalk_gov.sh` · `window_yabai.py`
—— 想恢复就 mv 回 `raycast/commands/`。
(`display_1080.sh` / `display_4k.sh` 在任何位置都不存在,已从清单删除。)
