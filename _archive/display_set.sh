#!/bin/bash
# Shared display resolution setter.
# Usage: display_set.sh [4k|1080]

MODE="${1:-4k}"

case "$MODE" in
    4k)
        RES="3840x2160"
        LABEL="4K"
        ;;
    1080)
        RES="1920x1080"
        LABEL="1080p（演示模式）"
        ;;
    *)
        echo "Usage: display_set.sh [4k|1080]"
        exit 1
        ;;
esac

source ~/Dev/tools/dev/lib/log_usage.sh

CURRENT_CONFIG=$(displayplacer list 2>/dev/null | tail -1)

if [ -z "$CURRENT_CONFIG" ]; then
    echo "❌ 无法获取显示器配置"
    exit 1
fi

CMD="displayplacer"
FOUND=false

while IFS= read -r config; do
    if echo "$config" | grep -q "2560x1664\|built in"; then
        continue
    fi
    id=$(echo "$config" | grep -oE 'id:[^ ]+' | head -1)
    origin=$(echo "$config" | grep -oE 'origin:\([^)]+\)')
    if [ -n "$id" ] && [ -n "$origin" ]; then
        CMD="$CMD \"$id res:$RES hz:60 color_depth:8 scaling:off $origin\""
        FOUND=true
    fi
done <<< "$(echo "$CURRENT_CONFIG" | tr '"' '\n' | grep "^id:")"

if [ "$FOUND" = false ]; then
    echo "❌ 未检测到外接显示器"
    exit 1
fi

eval $CMD 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ 外接显示器已切换到 $LABEL"
else
    echo "❌ 切换失败"
fi
