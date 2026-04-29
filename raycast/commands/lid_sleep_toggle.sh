#!/bin/bash

# Raycast parameters
# @raycast.schemaVersion 1
# @raycast.title Toggle Lid Sleep
# @raycast.mode fullOutput
# @raycast.icon 💤
# @raycast.packageName System
# @raycast.refreshTime 1s

# Documentation:
# @raycast.description 切换盒盖睡眠（盒盖时让 Mac 不睡，CC / 长任务继续跑）。已配 passwordless sudo (/etc/sudoers.d/pmset-toggle)，免密码。
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
    echo "❌ sudo 失败 — /etc/sudoers.d/pmset-toggle 没装好？"
    echo ""
    echo "重装："
    echo "  cat > /tmp/p <<EOF"
    echo "  tianli ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0"
    echo "  tianli ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1"
    echo "  EOF"
    echo "  sudo install -m 440 -o root -g wheel /tmp/p /etc/sudoers.d/pmset-toggle"
    exit 1
fi

echo ""
if [ "$NEW" = "1" ]; then
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   🔥🔥🔥   盒盖不睡眠 已开启   🔥🔥🔥                    ║
║                                                          ║
║   ✓ 盖上 lid → CPU / WiFi / CC 继续跑                    ║
║   ✓ 长任务 / 远程会话 / 下载 不会断                      ║
║                                                          ║
║   ⚠️  插电！别压被子里！会发热！                         ║
║   ⚠️  完事再跑一次切回省电模式                            ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
else
    cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   ✅✅✅   已恢复默认（盒盖会睡）   ✅✅✅                ║
║                                                          ║
║   盒盖正常进入睡眠，省电                                 ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
fi

echo ""
echo "── 当前 pmset 状态 ──"
pmset -g | grep -E "SleepDisabled|^ sleep " | sed 's/^/  /'
