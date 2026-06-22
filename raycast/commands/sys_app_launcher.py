#!/usr/bin/env python3
# @raycast.schemaVersion 1
# @raycast.title Launch Essential Apps
# @raycast.mode fullOutput
# @raycast.icon 🚀
# @raycast.packageName System
# @raycast.description 按 ~/Desktop/essential_apps.txt 批量拉起工作环境(GUI app + CLI 服务)
import sys, os; sys.path.insert(0, os.path.expanduser("~/Dev/tools/dev/lib"))
import log_usage  # noqa: F401  (import 即埋点)

import os
import re
import subprocess
import time

ESSENTIAL_APPS_FILE = os.path.realpath(os.path.expanduser("~/Desktop/essential_apps.txt"))
RUNNING_APPS_FILE = os.path.realpath(os.path.expanduser("~/Desktop/running_apps.txt"))

# 非 GUI 的 CLI 后台服务 —— 这些登录自启已取消,用本命令按需拉起。
# 启动方式只「运行」不重新注册开机自启(brew services run / nohup),保持登录极简。
BREW = "/opt/homebrew/bin/brew"
NODE = "/opt/homebrew/opt/node/bin/node"
_OPENCLAW_JS = os.path.expanduser(
    "~/Library/pnpm/global/5/.pnpm/"
    "openclaw@2026.3.7_@napi-rs+canvas@0.1.96_@types+express@5.0.6_hono@4.12.5_"
    "node-llama-cpp@3.16.2_typescript@5.9.3_/node_modules/openclaw/dist/index.js"
)
# name -> (进程匹配模式用于查重, 启动 argv)。
# yabai/skhd 来自第三方 tap, `brew services run` 会被拒(untrusted tap), 必须直接跑二进制
# (配置自动读 ~/.config/{yabai,skhd}/)。长驻二进制用 Popen 脱离, brew services run 用 run。
SERVICES = {
    "yabai":     ("yabai",     ["/opt/homebrew/bin/yabai"]),
    "skhd":      ("skhd",      ["/opt/homebrew/bin/skhd"]),
    "ollama":    ("ollama",    ["/opt/homebrew/bin/ollama", "serve"]),
    "syncthing": ("syncthing", ["/opt/homebrew/bin/syncthing", "serve", "--no-browser"]),
    "xray":      ("xray",      [BREW, "services", "run", "xray"]),
    "lucarned":  ("lucarned",  [BREW, "services", "run", "lucarned"]),
    "openclaw":  ("openclaw",  [NODE, _OPENCLAW_JS, "gateway", "--port", "18789"]),
}


def is_service_running(pattern):
    return subprocess.run(["pgrep", "-f", pattern], capture_output=True).returncode == 0


def start_service(name):
    spec = SERVICES.get(name)
    if not spec:
        print(f"❌ 未知服务: {name}（可用: {', '.join(SERVICES)}）")
        return
    pattern, argv = spec
    if is_service_running(pattern):
        print(f"  ✓ 服务已在运行: {name}")
        return
    print(f"ℹ️ 启动服务: {name}")
    try:
        if "services" in argv:  # brew services run: 快速返回,捕获错误
            r = subprocess.run(argv, capture_output=True, text=True, timeout=30)
            if r.returncode != 0:
                print(f"❌ 启动失败 {name}: {(r.stderr or r.stdout).strip().splitlines()[-1:]}")
                return
        else:  # 长驻二进制(yabai/skhd/ollama/syncthing/openclaw): Popen 脱离会话存活
            subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        print(f"✅ 已启动服务: {name}")
    except Exception as e:
        print(f"❌ 启动失败 {name}: {e}")


def get_running_apps():
    """获取当前运行的应用程序列表"""
    print("ℹ️ 正在获取当前运行的应用程序列表...")
    result = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True)
    apps = set()
    for line in result.stdout.split("\n"):
        if ".app/" in line:
            match = re.search(r"/([^/]*\.app)/", line)
            if match:
                apps.add(match.group(1))
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
    with open(RUNNING_APPS_FILE, "w") as f:
        f.write("\n".join(sorted(apps)))
    print(f"✅ 已更新运行应用列表 (找到 {len(apps)} 个)")
    return apps


def clean_app_name(name):
    name = re.sub(r" \([^)]*\)$", "", name)
    if not name.endswith(".app"):
        name += ".app"
    return name


def launch_app(app_name):
    clean_name = clean_app_name(app_name)
    print(f"ℹ️ 正在启动: {clean_name}")
    paths = [
        f"/Applications/{clean_name}",
        os.path.expanduser(f"~/Applications/{clean_name}"),
        f"/System/Applications/{clean_name}",
    ]
    for path in paths:
        if os.path.isdir(path):
            if subprocess.run(["open", path], capture_output=True).returncode == 0:
                print(f"✅ 成功启动: {clean_name}")
                return True
    app_name_only = clean_name.replace(".app", "")
    if subprocess.run(["open", "-a", app_name_only], capture_output=True).returncode == 0:
        print(f"✅ 成功启动: {clean_name}")
        return True
    print(f"❌ 无法启动应用: {clean_name}")
    return False


def main():
    print("=== 应用启动管理器 ===")
    if not os.path.exists(ESSENTIAL_APPS_FILE):
        print(f"❌ 必需应用列表文件不存在: {ESSENTIAL_APPS_FILE}")
        print("每行一个: GUI app 写 App.app；CLI 服务写 service:<名>（如 service:yabai）")
        return

    with open(ESSENTIAL_APPS_FILE) as f:
        lines = f.readlines()
    if not lines:
        print("⚠️ 必需应用列表为空")
        return

    # 先分类: service: 前缀 = CLI 服务; 其余 = GUI app
    services_to_start, app_lines = [], []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("==") or line.startswith("--"):
            continue
        if line.lower().startswith("service:"):
            services_to_start.append(line.split(":", 1)[1].strip().lower())
        else:
            app_lines.append(line)

    # ① 启动 CLI 服务
    if services_to_start:
        print(f"\n⚙️  CLI 服务 {len(services_to_start)} 个:")
        for name in services_to_start:
            start_service(name)

    # ② 启动 GUI app(跳过已运行的)
    running_apps = get_running_apps()
    running_apps_lower = {a.lower() for a in running_apps}
    apps_to_launch, apps_already_running = [], []
    for line in app_lines:
        clean_name = clean_app_name(line)
        (apps_already_running if clean_name.lower() in running_apps_lower else apps_to_launch).append(clean_name)

    if apps_already_running:
        print("\nℹ️ 以下应用已在运行：")
        for app in apps_already_running:
            print(f"  ✓ {app}")
    if apps_to_launch:
        print(f"\nℹ️ 需要启动 {len(apps_to_launch)} 个应用")
        for app in apps_to_launch:
            launch_app(app)
            time.sleep(1)
        print("\n✅ 应用启动完成！")
    else:
        print("\n✅ 所有必需的应用都已在运行！")
    print("\n=== 完成 ===")


if __name__ == "__main__":
    main()
