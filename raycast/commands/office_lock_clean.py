#!/Users/tianli/Dev/.venv/bin/python3
# @raycast.schemaVersion 1
# @raycast.title Clean Office Lock Files
# @raycast.mode fullOutput
# @raycast.icon 🧹
# @raycast.packageName File Utils
# @raycast.description 在所有 Office(Word/Excel/PPT/OneNote/LibreOffice)关闭后,清理残留的 ~$ 锁/属主文件到废纸篓
import sys, os; sys.path.insert(0, os.path.expanduser("~/Dev/tools/dev/lib"))
import log_usage  # noqa: F401  (import 即埋点)
"""Office 残留锁文件清理器。

Microsoft Office 打开文档时会在同目录生成属主/锁文件 `~$<文件名>`(几百字节);
正常关闭会自动删除,但崩溃/强退/网盘同步冲突会残留。本工具:
  1. 先检测是否还有真正的 Office 进程在跑(精确匹配可执行路径,排除 ExcelWidget
     等 widget 和 "PassWORD" 类误匹配);
  2. 只有在「全部关闭」时才动手 —— 有任何 Office 在跑则中止(那些锁可能是活的);
  3. 把残留 ~$* (Office) 和 .~lock.*# (LibreOffice) 文件移到废纸篓(可恢复,不硬删)。

用法:
    python3 office_lock_clean.py                 # 全盘默认根目录,移到废纸篓
    python3 office_lock_clean.py --dry-run       # 预览,只列不动
    python3 office_lock_clean.py --force         # 跳过进程检查(谨慎)
    python3 office_lock_clean.py --roots ~/Desktop,~/Work   # 自定义扫描根
    python3 office_lock_clean.py --json          # 机器可读输出(供 Hammerspoon 用)

设计契约(铁律 #1.X 机械活=确定性脚本 / #7 删除走可恢复废纸篓):
  - 默认移废纸篓而非 rm -f,本机 rm 已 alias trash,脚本内显式移废纸篓更可审计;
  - 进程检查是权威闸门,Hammerspoon 调用时不传 --force,脚本自身二次把关。
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# 真正的 Office 应用可执行路径片段(精确匹配,排除 widget / "passWORD" 误匹配)
OFFICE_PROC_RE = r"MacOS/Microsoft (Word|Excel|PowerPoint|OneNote)"
LIBRE_PROC_RE = r"soffice\.bin"

# 默认扫描根(承载文档的目录;避开 Library/缓存)
DEFAULT_ROOTS = ["~/Dev", "~/Work", "~/Apps", "~/Archives",
                 "~/Downloads", "~/Documents", "~/Desktop"]

# 遍历时剪枝的重目录(不会有 Office 文档,且巨大)
PRUNE_DIRS = {"node_modules", ".git", ".venv", "venv", "__pycache__",
              ".Trash", "Library", ".cache", "site-packages", ".next", "dist"}

MAX_DEPTH = 7  # 相对每个根的最大递归深度


def office_running():
    """返回仍在运行的 Office 进程描述列表(空=已全部关闭)。"""
    procs = []
    for regex in (OFFICE_PROC_RE, LIBRE_PROC_RE):
        try:
            r = subprocess.run(["pgrep", "-fl", regex],
                               capture_output=True, text=True)
            procs += [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
        except FileNotFoundError:
            pass
    return procs


def is_lock_file(name: str) -> bool:
    """Office 属主/锁文件命名判定。"""
    if name.startswith("~$"):
        return True
    if name.startswith(".~lock.") and name.endswith("#"):  # LibreOffice
        return True
    return False


def find_lock_files(roots):
    """在 roots 下遍历(剪枝+限深)收集残留锁文件路径。"""
    found = []
    for root in roots:
        base = Path(os.path.expanduser(root))
        if not base.is_dir():
            continue
        base_depth = len(base.parts)
        for dirpath, dirnames, filenames in os.walk(base):
            depth = len(Path(dirpath).parts) - base_depth
            if depth >= MAX_DEPTH:
                dirnames[:] = []
            else:
                dirnames[:] = [d for d in dirnames if d not in PRUNE_DIRS]
            for fn in filenames:
                if is_lock_file(fn):
                    found.append(Path(dirpath) / fn)
    return found


def trash_files(files, dry_run):
    """移到 ~/.Trash/office-lock-clean-<ts>/(可恢复)。返回成功移动的路径列表。"""
    if not files:
        return []
    if dry_run:
        return files
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = Path.home() / ".Trash" / f"office-lock-clean-{ts}"
    dest.mkdir(parents=True, exist_ok=True)
    moved = []
    for f in files:
        try:
            target = dest / f.name
            n = 1
            while target.exists():  # 防同名碰撞
                target = dest / f"{f.name}.{n}"
                n += 1
            shutil.move(str(f), str(target))
            moved.append(f)
        except OSError as e:
            print(f"  ⚠️  跳过 {f}: {e}", file=sys.stderr)
    return moved


def main():
    ap = argparse.ArgumentParser(description="清理残留 Office ~$ 锁文件")
    ap.add_argument("--dry-run", action="store_true", help="只列出不删除")
    ap.add_argument("--force", action="store_true", help="跳过 Office 进程检查")
    ap.add_argument("--roots", help="逗号分隔的扫描根(覆盖默认)")
    ap.add_argument("--json", action="store_true", help="JSON 输出")
    args = ap.parse_args()

    roots = args.roots.split(",") if args.roots else DEFAULT_ROOTS

    # 闸门 1: 进程检查
    running = [] if args.force else office_running()
    if running:
        msg = {"status": "aborted", "reason": "office_running",
               "running": running, "deleted": []}
        if args.json:
            print(json.dumps(msg, ensure_ascii=False))
        else:
            print("⏸  仍有 Office 进程在运行,不清理(锁可能是活的):")
            for p in running:
                print(f"    • {p}")
            print("   全部关闭后再跑,或加 --force 强制。")
        sys.exit(0)

    # 收集
    files = find_lock_files(roots)
    moved = trash_files(files, args.dry_run)

    result = {
        "status": "dry-run" if args.dry_run else "cleaned",
        "found": [str(f) for f in files],
        "deleted": [str(f) for f in moved],
        "count": len(moved),
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
        return

    if not files:
        print("✅ Office 已全部关闭,未发现残留 ~$ 锁文件。")
        return
    verb = "将清理(dry-run)" if args.dry_run else "已移到废纸篓"
    print(f"🧹 {verb} {len(files)} 个残留 Office 锁文件:")
    for f in files:
        print(f"    • {f}")
    if not args.dry_run:
        print(f"\n♻️  可在废纸篓 office-lock-clean-* 文件夹恢复。")


if __name__ == "__main__":
    main()
