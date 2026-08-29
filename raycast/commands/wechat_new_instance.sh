#!/bin/bash
# Raycast Script Command — 新开一个微信实例（多开）
#
# @raycast.schemaVersion 1
# @raycast.title 新开微信
# @raycast.mode compact
# @raycast.packageName WeChat
# @raycast.icon 💬
# @raycast.argument1 { "type": "text", "placeholder": "实例号(留空=下一个空闲)", "optional": true }
# @raycast.description 克隆官方 WeChat.app 成独立 bundle id 的副本并启动，各实例数据互相隔离
source ~/Dev/tools/dev/lib/log_usage.sh raycast
#
# 原理（2026-08-28 本机 WeChat 4.1.13 实测）：
#   · open -n 与直跑二进制都被单实例检查挡掉（第二实例静默自退）
#   · 唯一成立的路：ditto 官方 bundle → 改 CFBundleIdentifier → **剥掉 sandbox 相关
#     entitlement** → adhoc 重签。保留 app-sandbox/application-identifier/
#     application-groups/temporary-exception.* 会因绑死 TeamID 5A4RE8SF68 而秒退。
#   · 源必须是 /Applications/WeChat.app（官方原版）；~/Applications/WeChat.app
#     是被注入 wechat.dylib 并 adhoc 重签过的版本，拿它做源会把补丁带过去。
set -euo pipefail

SRC="/Applications/WeChat.app"
DSTDIR="$HOME/Applications"
BINREL="Contents/MacOS/WeChat"

die() { echo "$1"; exit 1; }
[ -d "$SRC" ] || die "❌ 找不到官方 $SRC（多开源必须是它，不是 ~/Applications 那份改过的）"

running() {  # $1=bundle 路径 → 该实例主进程是否在跑
  pgrep -f "^${1}/${BINREL}\$" >/dev/null 2>&1
}

N="${1:-}"
if [ -z "$N" ]; then                       # 没给实例号 → 找第一个没在跑的槽位
  for i in $(seq 2 9); do
    if ! running "$DSTDIR/WeChat${i}.app"; then N=$i; break; fi
  done
  [ -n "$N" ] || die "❌ 2-9 号实例都在跑了"
fi
case "$N" in ''|*[!0-9]*) die "❌ 实例号要是数字：$N";; esac
[ "$N" -ge 2 ] || die "❌ 1 号就是原版微信，直接 open /Applications/WeChat.app"

DST="$DSTDIR/WeChat${N}.app"

if running "$DST"; then
  open "$DST"; echo "微信 #${N} 已在运行，已切到前台"; exit 0
fi

if [ ! -d "$DST" ]; then                   # 首次：造这个副本（1.3G，约 20-40s）
  echo "首次创建微信 #${N}（复制 1.3G + 重签，请稍候）…"
  TMPENT="$(mktemp -t wxent).plist"; TMPENT2="$(mktemp -t wxent2).plist"
  trap 'rm -f "$TMPENT" "$TMPENT2"' EXIT
  /usr/bin/ditto "$SRC" "$DST"
  /usr/bin/defaults write "$DST/Contents/Info.plist" CFBundleIdentifier "com.tencent.xinWeChat${N}"
  /usr/bin/defaults write "$DST/Contents/Info.plist" CFBundleName "WeChat${N}"
  /usr/bin/plutil -convert xml1 "$DST/Contents/Info.plist"
  codesign -d --entitlements - --xml "$SRC" > "$TMPENT" 2>/dev/null
  /usr/bin/python3 - "$TMPENT" "$TMPENT2" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
for k in ("com.apple.application-identifier",
          "com.apple.security.app-sandbox",
          "com.apple.security.application-groups",
          "com.apple.security.temporary-exception.mach-lookup.global-name",
          "com.apple.security.temporary-exception.sbpl"):
    d.pop(k, None)
plistlib.dump(d, open(sys.argv[2], 'wb'))
PY
  codesign --force --deep --sign - --entitlements "$TMPENT2" "$DST" >/dev/null 2>&1 \
    || die "❌ 重签失败，已删残件：$(rm -rf "$DST"; echo "$DST")"
fi

open "$DST"
for _ in $(seq 1 20); do running "$DST" && break; sleep 1; done
running "$DST" || die "❌ 微信 #${N} 起不来（副本可能因微信更新与系统不匹配，删掉 $DST 重跑本命令重建）"
echo "✅ 微信 #${N} 已启动（数据独立：~/Library/Containers/com.tencent.xinWeChat${N}）"
