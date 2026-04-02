#!/bin/bash

# Raycast parameters
# @raycast.schemaVersion 1
# @raycast.title display_4k
# @raycast.mode fullOutput
# @raycast.icon 🖥️
# @raycast.packageName Display

# Documentation:
# @raycast.description Set external displays to 4K (3840x2160)

# 获取当前配置命令
CURRENT_CONFIG=$(displayplacer list 2>/dev/null | tail -1)

if [ -z "$CURRENT_CONFIG" ]; then
    echo "❌ 无法获取显示器配置"
    exit 1
fi

# 提取外接显示器配置并修改分辨率，保留 origin
CMD="displayplacer"
FOUND=false

# 解析每个显示器配置
while IFS= read -r config; do
    # 跳过内置屏幕
    if echo "$config" | grep -q "2560x1664\|built in"; then
        continue
    fi

    # 提取 id 和 origin
    id=$(echo "$config" | grep -oE 'id:[^ ]+' | head -1)
    origin=$(echo "$config" | grep -oE 'origin:\([^)]+\)')

    if [ -n "$id" ] && [ -n "$origin" ]; then
        CMD="$CMD \"$id res:3840x2160 hz:60 color_depth:8 scaling:off $origin\""
        FOUND=true
    fi
done <<< "$(echo "$CURRENT_CONFIG" | tr '"' '\n' | grep "^id:")"

if [ "$FOUND" = false ]; then
    echo "❌ 未检测到外接显示器"
    exit 1
fi

eval $CMD 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ 外接显示器已切换到 4K"
else
    echo "❌ 切换失败"
fi
