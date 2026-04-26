#!/usr/bin/env python3
# @raycast.schemaVersion 1
# @raycast.title 复制 Finder 选中路径
# @raycast.mode silent
# @raycast.icon 📋
# @raycast.packageName File Utils
# @raycast.description 复制 Finder 选中文件的路径或名称到剪贴板

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib"))

from display import show_error, show_info, show_success
from finder import get_input_files


def copy_to_clipboard(text):
    """复制文本到剪贴板"""
    subprocess.run(["pbcopy"], input=text.encode(), check=True)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "name"
    files = get_input_files([], allow_multiple=True)

    if not files:
        return

    if mode == "content":
        content_parts = []
        count = 0
        for file_path in files:
            filename = os.path.basename(file_path)
            if not os.path.isfile(file_path):
                show_info(f"跳过非文件: {filename}")
                continue
            try:
                with open(file_path, encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                content_parts.append(f"文件名：{filename}\n\n{content}\n\n-----------------------------------\n")
                count += 1
            except Exception as e:
                show_info(f"无法读取文件: {filename} ({e})")

        if content_parts:
            copy_to_clipboard("\n".join(content_parts))
            show_success(f"已复制 {count} 个文件的名称和内容到剪贴板")
        else:
            show_error("没有可复制的内容")
    else:
        filenames = [os.path.basename(f) for f in files]
        copy_to_clipboard("\n".join(filenames))
        show_success(f"已复制 {len(filenames)} 个文件的名称到剪贴板")


if __name__ == "__main__":
    main()
