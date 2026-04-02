#!/usr/bin/env python3
"""
Yabai 窗口管理统一工具

用法: python3 yabai.py <子命令>

子命令:
  float   切换当前窗口浮动
  mouse   切换鼠标跟随焦点
  org     整理窗口布局（bsp 平铺后切回 float）
  toggle  启动/停止 yabai 服务
"""

import subprocess
import sys


def cmd_float():
    subprocess.run(["yabai", "-m", "window", "--toggle", "float"])


def cmd_mouse():
    result = subprocess.run(["yabai", "-m", "config", "mouse_follows_focus"], capture_output=True, text=True)
    current = result.stdout.strip()
    if current == "off":
        subprocess.run(["yabai", "-m", "config", "mouse_follows_focus", "on"])
        print("mouse_follows_focus: ON")
    else:
        subprocess.run(["yabai", "-m", "config", "mouse_follows_focus", "off"])
        print("mouse_follows_focus: OFF")


def cmd_org():
    subprocess.run(["yabai", "-m", "space", "--layout", "bsp"], capture_output=True)
    subprocess.run(["yabai", "-m", "space", "--balance"], capture_output=True)
    subprocess.run(["yabai", "-m", "space", "--layout", "float"], capture_output=True)


def cmd_toggle():
    r = subprocess.run(["pgrep", "-x", "yabai"], capture_output=True)
    if r.returncode == 0:
        subprocess.run(["yabai", "--stop-service"])
        print("yabai stopped")
    else:
        subprocess.run(["yabai", "--start-service"])
        print("yabai started")


COMMANDS = {"float": cmd_float, "mouse": cmd_mouse, "org": cmd_org, "toggle": cmd_toggle}

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else None
    if cmd in COMMANDS:
        COMMANDS[cmd]()
    else:
        print(__doc__)
