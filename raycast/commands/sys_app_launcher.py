#!/usr/bin/env python3
# @raycast.schemaVersion 1
# @raycast.title Launch Essential Apps
# @raycast.mode fullOutput
# @raycast.icon 🚀
# @raycast.packageName System
# @raycast.description 按 ~/Desktop/essential_apps.txt 批量启动应用

import os
import re
import subprocess

ESSENTIAL_APPS_FILE = os.path.realpath(os.path.expanduser("~/Desktop/essential_apps.txt"))
RUNNING_APPS_FILE = os.path.realpath(os.path.expanduser("~/Desktop/running_apps.txt"))


def get_running_apps():
    """获取当前运行的应用程序列表"""
    print("ℹ️ 正在获取当前运行的应用程序列表...")

    # 方法1: 通过 ps 命令
    result = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True)
    apps = set()
    for line in result.stdout.split("\n"):
        if ".app/" in line:
            match = re.search(r"/([^/]*\.app)/", line)
            if match:
                apps.add(match.group(1))

    # 方法2: 通过 AppleScript
    if len(apps) < 5:
        script = """
        tell application "System Events"
            set runningApps to name of every application process whose background only is false
        end tell
        return runningApps
        """
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        for app_name in result.stdout.split(","):
            app_name = app_name.strip()
            if app_name:
                if not app_name.endswith(".app"):
                    app_name += ".app"
                apps.add(app_name)

    # 保存到文件
    with open(RUNNING_APPS_FILE, "w") as f:
        f.write("\n".join(sorted(apps)))

    print(f"✅ 已更新运行应用列表 (找到 {len(apps)} 个)")
    return apps


def clean_app_name(name):
    """清理应用名称"""
    name = re.sub(r" \([^)]*\)$", "", name)  # 移除括号后缀
    if not name.endswith(".app"):
        name += ".app"
    return name


def launch_app(app_name):
    """启动应用程序"""
    clean_name = clean_app_name(app_name)
    print(f"ℹ️ 正在启动: {clean_name}")

    # 尝试不同的路径
    paths = [
        f"/Applications/{clean_name}",
        os.path.expanduser(f"~/Applications/{clean_name}"),
        f"/System/Applications/{clean_name}",
    ]

    for path in paths:
        if os.path.isdir(path):
            result = subprocess.run(["open", path], capture_output=True)
            if result.returncode == 0:
                print(f"✅ 成功启动: {clean_name}")
                return True

    # 尝试使用 -a 选项
    app_name_only = clean_name.replace(".app", "")
    result = subprocess.run(["open", "-a", app_name_only], capture_output=True)
    if result.returncode == 0:
        print(f"✅ 成功启动: {clean_name}")
        return True

    print(f"❌ 无法启动应用: {clean_name}")
    return False


def main():
    print("=== 应用启动管理器 ===")

    # 检查必需文件
    if not os.path.exists(ESSENTIAL_APPS_FILE):
        print(f"❌ 必需应用列表文件不存在: {ESSENTIAL_APPS_FILE}")
        print("请创建该文件并添加需要启动的应用名称（每行一个，格式如：App.app）")
        return

    # 获取当前运行的应用
    running_apps = get_running_apps()
    running_apps_lower = {a.lower() for a in running_apps}

    # 读取必需应用列表
    with open(ESSENTIAL_APPS_FILE) as f:
        lines = f.readlines()

    if not lines:
        print("⚠️ 必需应用列表为空")
        return

    apps_to_launch = []
    apps_already_running = []

    for line in lines:
        line = line.strip()
        # 跳过空行和注释
        if not line or line.startswith("#") or line.startswith("==") or line.startswith("--"):
            continue

        clean_name = clean_app_name(line)

        if clean_name.lower() in running_apps_lower:
            apps_already_running.append(clean_name)
        else:
            apps_to_launch.append(clean_name)

    # 显示已运行的应用
    if apps_already_running:
        print("\nℹ️ 以下应用已在运行：")
        for app in apps_already_running:
            print(f"  ✓ {app}")

    # 启动缺失的应用
    if apps_to_launch:
        print(f"\nℹ️ 需要启动 {len(apps_to_launch)} 个应用")
        for app in apps_to_launch:
            launch_app(app)
            import time

            time.sleep(1)
        print("\n✅ 应用启动完成！")
    else:
        print("\n✅ 所有必需的应用都已在运行！")

    print("\n=== 完成 ===")


if __name__ == "__main__":
    main()
