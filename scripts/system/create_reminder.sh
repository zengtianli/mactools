#!/bin/bash

# Apple 提醒事项创建脚本
# 使用 AppleScript 与 Reminders.app 交互

# 参数：
# $1 - 提醒内容（必需）
# $2 - 提醒时间（可选，格式：YYYY-MM-DD HH:MM）
# $3 - 列表名称（可选，默认为 "Reminders"）
# --dry-run - 测试模式，仅输出命令不实际执行

# 解析参数
DRY_RUN=false
ARGS=()

for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=true
    else
        ARGS+=("$arg")
    fi
done

REMINDER_TEXT="${ARGS[0]}"
REMINDER_TIME="${ARGS[1]}"
LIST_NAME="${ARGS[2]:-Reminders}"

# 验证必需参数
if [ -z "$REMINDER_TEXT" ]; then
    echo "❌ 错误：请提供提醒内容"
    echo "用法: $0 <提醒内容> [时间] [列表名称] [--dry-run]"
    echo "示例: $0 \"查看工作报告\" \"2026-03-02 18:00\" \"work\""
    exit 1
fi

# 构建 AppleScript
if [ -z "$REMINDER_TIME" ]; then
    # 无时间的提醒
    APPLESCRIPT="tell application \"Reminders\"
    tell list \"$LIST_NAME\"
        make new reminder with properties {name:\"$REMINDER_TEXT\"}
    end tell
end tell"
else
    # 带时间的提醒
    APPLESCRIPT="tell application \"Reminders\"
    tell list \"$LIST_NAME\"
        set newReminder to make new reminder with properties {name:\"$REMINDER_TEXT\"}
        set remind me date of newReminder to date \"$REMINDER_TIME\"
    end tell
end tell"
fi

# 执行或输出
if [ "$DRY_RUN" = true ]; then
    echo "🧪 测试模式 - 将执行以下 AppleScript："
    echo "---"
    echo "$APPLESCRIPT"
    echo "---"
    echo "提醒内容: $REMINDER_TEXT"
    [ -n "$REMINDER_TIME" ] && echo "提醒时间: $REMINDER_TIME"
    echo "列表名称: $LIST_NAME"
else
    osascript -e "$APPLESCRIPT"
    if [ $? -eq 0 ]; then
        echo "✅ 提醒已创建：$REMINDER_TEXT"
        [ -n "$REMINDER_TIME" ] && echo "   时间：$REMINDER_TIME"
        echo "   列表：$LIST_NAME"
    else
        echo "❌ 创建提醒失败"
        exit 1
    fi
fi
