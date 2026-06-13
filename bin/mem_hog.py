#!/usr/bin/env python3
"""mem_hog.py — 按 .app 聚合内存占用 + 诚实给出「该关哪个」建议。

只读，不杀进程(给建议,用户自己决定;--kill 可选交互关)。
聚合逻辑:同一 .app 的多个 helper 进程归并(浏览器/Electron 常几十个子进程)。
判断逻辑:白名单(系统/CC 工作必需)永不建议关;浏览器堆标签→建议重启;
开发重型工具→不用就退;其余 top 占用→中性「按需」。

用法:
  python3 mem_hog.py            # top 15 + 建议
  python3 mem_hog.py -n 25      # top 25
  python3 mem_hog.py --kill     # 交互式关闭建议项(可逆,随时再开)
"""
import subprocess
import sys
import os

# 永不建议关:系统关键 / CC 当前工作进程 / 终端 / 输入法 / 菜单栏
KEEP = {
    "claude", "node", "WindowServer", "Finder", "Dock", "SystemUIServer",
    "Cardinal", "Ghostty", "Terminal", "iTerm2", "ControlCenter", "Stats",
    "loginwindow", "coreaudiod", "SogouInput", "SetStoreUpdateService",
    "Shadowrocket", "mds_stores", "mdworker_shared", "com.apple.WebKit.WebContent",
    "WiFiAgent", "com.apple.DriverKit-AppleBCMWLAN", "kernel_task",
}
# 浏览器:多进程堆标签,重启清最划算
BROWSERS = {
    "Dia", "Google Chrome", "Safari", "Arc", "Firefox", "Microsoft Edge",
    "Brave Browser", "Chromium", "Opera", "Vivaldi",
}
# 开发/重型可选工具:不在用就纯浪费
DEV_HEAVY = {
    "wechatwebdevtools", "Xcode", "Docker", "Docker Desktop", "Simulator",
    "Android Studio", "qemu", "VirtualBox", "Parallels Desktop",
    "IntelliJ IDEA", "PyCharm", "Visual Studio Code", "Code",
}


def human(kb):
    g = kb / 1024 / 1024
    if g >= 1:
        return f"{g:5.2f} GB"
    return f"{kb/1024:5.0f} MB"


def app_of(path):
    """从进程路径提取 .app 名作为聚合键。"""
    import re
    m = re.search(r"/([^/]+)\.app/", path)
    if m:
        return m.group(1)
    return os.path.basename(path)


def gather():
    out = subprocess.run(
        ["ps", "-axro", "rss,comm"], capture_output=True, text=True
    ).stdout
    agg = {}
    for line in out.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) < 2:
            continue
        try:
            rss = int(parts[0])
        except ValueError:
            continue
        app = app_of(parts[1])
        e = agg.setdefault(app, [0, 0])
        e[0] += rss
        e[1] += 1
    return sorted(agg.items(), key=lambda kv: -kv[1][0])


def sysinfo():
    memsize = int(subprocess.run(["sysctl", "-n", "hw.memsize"],
                                 capture_output=True, text=True).stdout)
    swap = subprocess.run(["sysctl", "-n", "vm.swapusage"],
                          capture_output=True, text=True).stdout.strip()
    # vm.swapusage: total = 4096.00M  used = 3723.50M  free = 372.50M
    su = {}
    for tok in ("total", "used", "free"):
        try:
            i = swap.index(tok)
            val = swap[i:].split("=")[1].strip().split()[0]
            su[tok] = float(val.rstrip("M"))
        except (ValueError, IndexError):
            su[tok] = 0.0
    try:
        mp = subprocess.run(["memory_pressure"], capture_output=True,
                            text=True).stdout
        free_pct = next((l.split(":")[1].strip() for l in mp.splitlines()
                         if "free percentage" in l), "?")
    except Exception:
        free_pct = "?"
    return memsize / 1024**3, su, free_pct


def classify(app, kb):
    gb = kb / 1024 / 1024
    if app in KEEP:
        return ("🔒", "工作/系统必需 · 留")
    if app in BROWSERS:
        if gb >= 1.5:
            return ("🌐", "浏览器标签堆积 → 重启它清最多")
        return ("🌐", "浏览器 · 在用就留")
    if app in DEV_HEAVY:
        return ("🛠", "重型开发工具 → 没在用就退出(纯浪费)")
    if gb >= 1.0:
        return ("⚠️", "占用高 → 没在用建议退出")
    if gb >= 0.4:
        return ("·", "中等 · 按需")
    return ("·", "")


def suggest_targets(rows):
    """返回(app, kb, reason)的建议关闭列表。"""
    targets = []
    for app, (kb, _c) in rows:
        gb = kb / 1024 / 1024
        if app in KEEP:
            continue
        if app in BROWSERS and gb >= 1.5:
            targets.append((app, kb, "重启清标签"))
        elif app in DEV_HEAVY and gb >= 0.3:
            targets.append((app, kb, "没在用就退出"))
        elif gb >= 1.0:
            targets.append((app, kb, "占用高,没在用就退"))
    return targets


def main():
    n = 15
    do_kill = "--kill" in sys.argv
    if "-n" in sys.argv:
        try:
            n = int(sys.argv[sys.argv.index("-n") + 1])
        except (ValueError, IndexError):
            pass

    rows = gather()
    total_gb, swap, free_pct = sysinfo()

    swap_used = swap.get("used", 0)
    swap_total = swap.get("total", 1) or 1
    swap_warn = " ⚠️ 快爆" if swap_used / swap_total > 0.8 else ""
    print(f"🧠 内存大户  ·  总 {total_gb:.0f}GB  ·  空闲 {free_pct}"
          f"  ·  swap {swap_used/1024:.1f}/{swap_total/1024:.1f}GB{swap_warn}")
    print("─" * 56)

    for app, (kb, cnt) in rows[:n]:
        icon, note = classify(app, kb)
        print(f"  {human(kb)}  {cnt:>3}进程  {icon} {app:<22} {note}")

    targets = suggest_targets(rows[:n])
    if targets:
        total_free = sum(t[1] for t in targets) / 1024 / 1024
        print("─" * 56)
        names = "、".join(t[0] for t in targets)
        print(f"💡 立即可释放 ≈ {total_free:.1f}GB:{names}")
        for app, kb, why in targets:
            print(f"     · {app}({human(kb).strip()}) — {why}")
    else:
        print("─" * 56)
        print("✅ 无明显可释放的大户(top 占用都是工作/系统必需)")

    if do_kill and targets:
        print()
        for app, kb, why in targets:
            ans = input(f"关闭 {app}（{why}）? [y/N] ").strip().lower()
            if ans == "y":
                r = subprocess.run(
                    ["osascript", "-e", f'tell application "{app}" to quit'],
                    capture_output=True, text=True)
                if r.returncode == 0:
                    print(f"  ✅ 已请求退出 {app}")
                else:
                    # 优雅退出失败 → pkill 兜底
                    subprocess.run(["pkill", "-f", app], capture_output=True)
                    print(f"  ✅ 已 pkill {app}")


if __name__ == "__main__":
    main()
