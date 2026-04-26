#!/usr/bin/env python3
# @raycast.schemaVersion 1
# @raycast.title Print Finder Selection
# @raycast.mode fullOutput
# @raycast.icon 🖨️
# @raycast.packageName File Utils
# @raycast.description 打印 Finder 当前选中的文件

import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib"))

from display import show_error, show_info, show_success
from finder import get_input_files

LPR_TYPES = {".pdf", ".jpg", ".jpeg", ".png", ".tiff", ".tif", ".gif", ".bmp", ".txt", ".ps", ".eps"}


def print_with_lpr(filepath: str, copies: int) -> bool:
    result = subprocess.run(["lpr", "-#", str(copies), filepath], capture_output=True, text=True)
    return result.returncode == 0


def print_with_system(filepath: str, copies: int) -> bool:
    script = f'''
    set filePath to POSIX file "{filepath}"
    tell application "Finder"
        print filePath
    end tell
    '''
    for _ in range(copies):
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return False
        if copies > 1:
            time.sleep(1)
    return True


def main():
    copies = 1
    if len(sys.argv) > 1 and sys.argv[1].strip():
        try:
            copies = int(sys.argv[1].strip())
            if copies < 1:
                copies = 1
        except ValueError:
            show_error(f"份数必须是数字: {sys.argv[1]}")
            return

    files = get_input_files([], allow_multiple=True)
    if not files:
        return

    printed = 0
    for f in files:
        name = Path(f).name
        ext = Path(f).suffix.lower()

        if ext in LPR_TYPES:
            ok = print_with_lpr(f, copies)
        else:
            ok = print_with_system(f, copies)

        if ok:
            show_info(f"已发送: {name}")
            printed += 1
        else:
            show_error(f"打印失败: {name}")

    if printed:
        copies_text = f" x{copies}" if copies > 1 else ""
        show_success(f"已发送 {printed} 个文件到打印机{copies_text}")


if __name__ == "__main__":
    main()
