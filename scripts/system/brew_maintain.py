#!/usr/bin/env python3
"""Homebrew 全量维护：升级 formula + 清理孤儿 cask + 升级在用 cask"""

import json
import os
import subprocess
import sys
import time


def get_cask_app_map():
    """批量获取所有已安装 cask 及其 .app 路径"""
    result = subprocess.run(
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
    auto = "--auto" in sys.argv

    print("🍺 Homebrew 全量维护")
    print("=" * 50)

    # 1. brew update
    print("\n📡 更新 Homebrew 索引...")
    subprocess.run(["brew", "update"], timeout=300)

    # 2. 升级 formula
    print("\n📦 检查 formula 更新...")
    result = subprocess.run(
        ["brew", "outdated", "--formula"],
        capture_output=True, text=True, timeout=120,
    )
    outdated_formulae = result.stdout.strip().split("\n") if result.stdout.strip() else []
    if outdated_formulae:
        print(f"   需升级：{', '.join(outdated_formulae)}")
        subprocess.run(["brew", "upgrade", "--formula"])
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

        if auto:
            do_remove = True
        else:
            ans = input(f"\n卸载这 {len(orphans)} 个？[Y/n] ").strip().lower()
            do_remove = ans in ("", "y", "yes")

        if do_remove:
            tokens = [t for t, _ in orphans]
            print(f"\n正在卸载 {len(tokens)} 个 cask...")
            subprocess.run(["brew", "uninstall", "--cask"] + tokens)
            print("✅ 孤儿清理完成")
        else:
            print("⏭️  跳过卸载")
    else:
        print("\n✅ 无孤儿 cask")

    # 5. 升级在用 cask
    print(f"\n⬆️  检查 {len(active)} 个在用 cask 的更新...")
    result = subprocess.run(
        ["brew", "outdated", "--cask", "--greedy"],
        capture_output=True, text=True, timeout=120,
    )
    outdated = set(result.stdout.strip().split("\n")) if result.stdout.strip() else set()
    to_upgrade = [t for t in active if t in outdated]

    if to_upgrade:
        print(f"   需升级（{len(to_upgrade)}个）：{', '.join(to_upgrade)}")
        cask_timeout = None  # 不限时，避免大包被误杀
        failed = []
        for i, token in enumerate(to_upgrade, 1):
            print(f"\n   [{i}/{len(to_upgrade)}] {token}...", flush=True)
            t0 = time.time()
            try:
                r = subprocess.run(
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

    # 6. cleanup
    print("\n🧹 清理缓存...")
    subprocess.run(["brew", "cleanup", "--prune=7"], timeout=60)
    print("\n✅ 维护完成")


if __name__ == "__main__":
    main()
