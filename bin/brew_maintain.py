#!/usr/bin/env python3
# 引擎(非 Raycast 命令)：2026-06-01 用户钦定 homebrew 只留后台命令 → 本文件降级为引擎,
# 仅被 brew_maintain_bg.sh 调用(brew_maintain.py --auto)。撤 @raycast.* 元数据,Raycast 不再注册。
# 2026-07-26: 全程非交互化 —— 默认不再问任何 y(卸载孤儿 cask 直接干),brew 子进程带
# NONINTERACTIVE=1 + stdin=DEVNULL。--auto 变 no-op(兼容旧调用),--ask 才恢复交互确认。
import sys, os; sys.path.insert(0, os.path.expanduser("~/Dev/tools/dev/lib"))
import log_usage  # noqa: F401  (import 即埋点)
"""Homebrew 全量维护：升级 formula + 清理孤儿 cask + 升级在用 cask"""

import json
import os
import subprocess
import sys
import time

EXCLUDE = {"claude", "typora"}

# 全程非交互：脚本自身不问 y（默认 = 干活），brew 子进程也别弹提示。
# HOMEBREW_NO_ASK=1 是关键那把——brew ≥4 的 "ask 模式"默认开启（cmd/upgrade.rb:
#   `ask = !args.no_ask?`），会先跑一遍 dry-run 预览再问 "Do you want to proceed?"，
#   这就是用户抱怨的第二个 y；NONINTERACTIVE 管不到它，必须单独关。顺带省掉预览那趟空跑。
# NONINTERACTIVE=1 关 brew 其余交互；NO_ENV_HINTS 去噪。
BREW_ENV = {
    **os.environ,
    "HOMEBREW_NO_ASK": "1",
    "NONINTERACTIVE": "1",
    "HOMEBREW_NO_ENV_HINTS": "1",
}


# 交互式跑（终端里）→ 继承 stdin，让少数需要 root 的 cask（如 quarto 卸旧版 pkg）
# 能弹 sudo 密码框；无人值守跑（cron / nohup / 管道）→ DEVNULL，宁可失败也别静默挂死。
# 踩坑 2026-07-26：一刀切 DEVNULL 导致 quarto 升级 `Error: quarto: Broken pipe`
# ——sudo 想要密码却没有输入通道。密码 ≠ y/n 确认，前者省不掉，后者才是要消灭的。
_TTY = sys.stdin.isatty()


def run(cmd, **kw):
    """所有 brew 调用统一走这里：注入非交互环境 + 按 tty 决定 stdin"""
    kw.setdefault("env", BREW_ENV)
    if not kw.get("capture_output"):
        kw.setdefault("stdin", None if _TTY else subprocess.DEVNULL)
    return subprocess.run(cmd, **kw)


def get_cask_app_map():
    """批量获取所有已安装 cask 及其 .app 路径"""
    result = run(
        ["brew", "info", "--json=v2", "--installed"],
        capture_output=True, text=True, timeout=120,
    )
    data = json.loads(result.stdout)

    cask_map = {}  # {token: [app_names]} or {token: None} for non-app casks
    for cask in data.get("casks", []):
        token = cask["token"]
        apps = []
        for a in cask.get("artifacts", []):
            if isinstance(a, dict) and "app" in a:
                for app in a["app"]:
                    if isinstance(app, str):
                        apps.append(app)
                    elif isinstance(app, dict) and "target" in app:
                        apps.append(app["target"])
        cask_map[token] = apps if apps else None
    return cask_map


def check_app_exists(app_name):
    for base in ["/Applications", os.path.expanduser("~/Applications")]:
        if os.path.exists(os.path.join(base, app_name)):
            return True
    return False


def main():
    # 默认全自动（不问 y）。--auto 保留兼容（已是默认，等价 no-op）；
    # --ask 才恢复卸载孤儿前的交互确认。
    ask = "--ask" in sys.argv

    print("🍺 Homebrew 全量维护")
    print("=" * 50)

    # 1. brew update
    print("\n📡 更新 Homebrew 索引...")
    run(["brew", "update"], timeout=300)

    # 2. 升级 formula
    print("\n📦 检查 formula 更新...")
    result = run(
        ["brew", "outdated", "--formula"],
        capture_output=True, text=True, timeout=120,
    )
    outdated_formulae = result.stdout.strip().split("\n") if result.stdout.strip() else []
    if outdated_formulae:
        print(f"   需升级：{', '.join(outdated_formulae)}")
        run(["brew", "upgrade", "--formula"])
        print("✅ Formula 升级完成")
    else:
        print("   全部已是最新")

    # 3. 分类
    print("\n🔍 扫描已安装 cask...")
    cask_map = get_cask_app_map()

    orphans = []  # cask 有 app artifact 但本地找不到
    active = []   # 本地在用
    non_app = []  # 字体/驱动等无 app

    for token, apps in sorted(cask_map.items()):
        if apps is None:
            non_app.append(token)
            continue
        if any(check_app_exists(a) for a in apps):
            active.append(token)
        else:
            orphans.append((token, apps))

    # 4. 处理孤儿
    if orphans:
        print(f"\n🗑️  发现 {len(orphans)} 个孤儿 cask（本地无对应 app）：")
        for token, apps in orphans:
            print(f"   {token:30s}  {', '.join(apps)}")

        if ask:
            ans = input(f"\n卸载这 {len(orphans)} 个？[Y/n] ").strip().lower()
            do_remove = ans in ("", "y", "yes")
        else:
            do_remove = True  # 默认 = 卸载（cask 可随时 brew install 装回）

        if do_remove:
            tokens = [t for t, _ in orphans]
            print(f"\n正在卸载 {len(tokens)} 个 cask...")
            run(["brew", "uninstall", "--cask"] + tokens)
            print("✅ 孤儿清理完成")
        else:
            print("⏭️  跳过卸载")
    else:
        print("\n✅ 无孤儿 cask")

    # 5. 升级在用 cask（含 non-app cask 如 CLI 工具、字体等）
    upgradable = active + non_app
    print(f"\n⬆️  检查 {len(upgradable)} 个在用 cask 的更新（含 {len(non_app)} 个 non-app）...")
    result = run(
        ["brew", "outdated", "--cask", "--greedy"],
        capture_output=True, text=True, timeout=120,
    )
    outdated = set(result.stdout.strip().split("\n")) if result.stdout.strip() else set()
    to_upgrade = [t for t in upgradable if t in outdated and t not in EXCLUDE]
    skipped = [t for t in upgradable if t in outdated and t in EXCLUDE]
    if skipped:
        print(f"   ⏭️  跳过排除清单：{', '.join(skipped)}")

    if to_upgrade:
        print(f"   需升级（{len(to_upgrade)}个）：{', '.join(to_upgrade)}")
        cask_timeout = None  # 不限时，避免大包被误杀
        failed = []
        for i, token in enumerate(to_upgrade, 1):
            print(f"\n   [{i}/{len(to_upgrade)}] {token}...", flush=True)
            t0 = time.time()
            try:
                r = run(
                    ["brew", "upgrade", "--cask", token],
                    timeout=cask_timeout,
                )
                elapsed = time.time() - t0
                if r.returncode != 0:
                    failed.append((token, "安装失败"))
                    print(f"   ⚠️  {token} 失败（{elapsed:.0f}s），继续下一个")
                else:
                    print(f"   ✔ {token}（{elapsed:.0f}s）")
            except subprocess.TimeoutExpired:
                failed.append((token, f"超时 >{cask_timeout}s"))
                print(f"   ⏰ {token} 超时跳过，继续下一个")
                # 终止残留的 brew 进程
                subprocess.run(["pkill", "-f", f"brew.*{token}"],
                               capture_output=True)
        if failed:
            print(f"\n⚠️  {len(failed)} 个 cask 升级失败：")
            for token, reason in failed:
                print(f"   {token}: {reason}")
            print("   可手动重试：brew upgrade --cask " + " ".join(t for t, _ in failed))
        else:
            print("\n✅ 全部升级完成")
    else:
        print("   全部已是最新")

    # 5.5 cleanup 前补升残留 formula
    # 根因：macOS 27 是 brew 非 Tier-1 配置，开头的 brew update 偶发拉取不全/被限流，
    # 导致 step 2 的 brew outdated 返回空 → 该升的没升 → cleanup 看到「最新版没装」
    # 就刷 `Skipping X: most recent version Y not installed` 警告。这里在 cleanup 前
    # 再核对一次 outdated（此时 DB 已被前面多步刷新），有残留就补一刀，让警告结构上消失。
    result = run(
        ["brew", "outdated", "--formula", "--quiet"],
        capture_output=True, text=True, timeout=120,
    )
    leftover = [x for x in result.stdout.strip().split("\n") if x]
    if leftover:
        print(f"\n🔁 cleanup 前补升残留 formula（{len(leftover)}个）：{', '.join(leftover)}")
        run(["brew", "upgrade", "--formula"])

    # 6. cleanup
    print("\n🧹 清理缓存...")
    run(["brew", "cleanup", "--prune=7"], timeout=60)
    print("\n✅ 维护完成")


if __name__ == "__main__":
    main()
