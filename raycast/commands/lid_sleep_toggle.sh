#!/bin/bash

# Raycast parameters
# @raycast.schemaVersion 1
# @raycast.title Toggle Lid Sleep
# @raycast.mode fullOutput
# @raycast.icon 💤
# @raycast.packageName System

# Documentation:
# @raycast.description 切换盒盖睡眠（盒盖时让 Mac 不睡，CC / 长任务继续跑）。详细输出当前电源、睡眠阻断进程、超时设置。已配 passwordless sudo。
# @raycast.author tianli

source ~/Dev/devtools/lib/log_usage.sh

CURRENT=$(pmset -g | awk '/SleepDisabled/ {print $2}')
[ -z "$CURRENT" ] && CURRENT=0

if [ "$CURRENT" = "1" ]; then
    NEW=0
else
    NEW=1
fi

if ! sudo -n pmset -a disablesleep "$NEW" 2>/dev/null; then
    echo "❌ sudo 失败 — /etc/sudoers.d/pmset-toggle 没装好"
    echo ""
    echo "重装："
    echo "  cat > /tmp/p.sudoers <<EOF"
    echo "  tianli ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0"
    echo "  tianli ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1"
    echo "  EOF"
    echo "  sudo install -m 440 -o root -g wheel /tmp/p.sudoers /etc/sudoers.d/pmset-toggle"
    exit 1
fi

# ─── Banner ────────────────────────────────────────────────
echo ""
if [ "$NEW" = "1" ]; then
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║      🔥🔥🔥   盒盖不睡眠 · ON   🔥🔥🔥                           ║
║                                                                  ║
║      盖上 lid → CPU / WiFi / CC / 长任务 全部继续                ║
║                                                                  ║
║      ⚠️   插电！别压被子！会发热！                               ║
║      ⚠️   完事再跑一次切回省电模式                               ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
else
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║      ✅✅✅   盒盖睡眠 · OFF（默认/省电）   ✅✅✅               ║
║                                                                  ║
║      盖上 lid 正常进入睡眠                                       ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
fi

# ─── Power Source ─────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔋 电源 · 电量"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
pmset -g batt | sed 's/^/  /'

# Warn if disablesleep=1 on battery
if [ "$NEW" = "1" ] && pmset -g batt | grep -q "Battery Power"; then
    echo ""
    echo "  ⚠️⚠️⚠️  当前用电池！盒盖不睡会快速掉电，建议立刻插电"
fi

# ─── Sleep Settings ────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💤 睡眠设置（pmset -g）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
pmset -g | awk '
    function row(label, key, val,    rest) {
        # val 是首个数字；后续可能有 "(sleep prevented by ...)"
        rest = ""
        for (i=3; i<=NF; i++) rest = rest " " $i
        printf "  %-18s %-3s%s\n", label, val, rest
    }
    /SleepDisabled/      { printf "  %-18s %-3s ← %s\n", "盒盖禁睡", $2, ($2=="1"?"🔥 ON（盖了不睡）":"省电 OFF（盖了会睡）"); next }
    /^[ \t]*sleep[ \t]/  { sub(/^[ \t]+/,""); row("系统空闲睡眠", $1, $2); next }
    /displaysleep/       { sub(/^[ \t]+/,""); row("屏幕睡眠 (min)", $1, $2); next }
    /disksleep/          { sub(/^[ \t]+/,""); row("硬盘睡眠 (min)", $1, $2); next }
    /networkoversleep/   { sub(/^[ \t]+/,""); row("WiFi 维持", $1, $2); next }
    /tcpkeepalive/       { sub(/^[ \t]+/,""); row("TCP keepalive", $1, $2); next }
    /powernap/           { sub(/^[ \t]+/,""); row("PowerNap", $1, $2); next }
    /lidwake/            { sub(/^[ \t]+/,""); row("开盖唤醒", $1, $2); next }
'

# ─── Active Sleep Assertions ──────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 谁在阻止睡眠（pmset -g assertions）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ASSERTIONS=$(pmset -g assertions 2>/dev/null | awk '
    /Listed by owning process:/ { p=1; next }
    /Kernel Assertions:/        { p=0 }
    p && /pid [0-9]+\(/ {
        match($0, /pid [0-9]+\([^)]+\)/);
        proc = substr($0, RSTART, RLENGTH);
        name = "";
        if (match($0, /named: "[^"]+"/)) {
            name = substr($0, RSTART+8, RLENGTH-9);   # 去掉 named: " 和尾 "
        }
        printf "  • %-32s %s\n", proc, name
    }
')
if [ -n "$ASSERTIONS" ]; then
    echo "$ASSERTIONS"
else
    echo "  （无显式阻断 — 系统按默认策略）"
fi

# ─── Caffeinate hint ───────────────────────────────────────
if [ "$NEW" = "1" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 双保险（可选）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  另开终端跑：caffeinate -dis &     （防屏幕暗 + 防系统空闲睡）"
    echo "  CC 进程放 tmux：                  tmux new -s cc"
fi

# ─── Final status line (Raycast compact preview shows this) ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$NEW" = "1" ]; then
    echo "✅ 已切换：盒盖不睡眠 ON 🔥  (SleepDisabled=1)  — 可以盖盒盖了"
else
    echo "✅ 已切换：盒盖睡眠 OFF 💤  (SleepDisabled=0)  — 已恢复省电默认"
fi
echo ""
