#!/bin/bash
# Raycast Script
# @raycast.schemaVersion 1
# @raycast.title folder_paste
# @raycast.mode fullOutput
# @raycast.icon 📋
# @raycast.packageName Custom
# @raycast.description 将剪贴板中的文件粘贴到 Finder 当前目录

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"

log_script_usage "folders/folder_paste.sh" "folders"

# 获取目标目录：优先使用选中的文件夹，否则用当前窗口目录
TARGET_DIR=$(osascript -e '
tell application "Finder"
    set sel to selection as list
    if (count of sel) > 0 then
        set firstItem to item 1 of sel
        if class of firstItem is folder then
            return POSIX path of (firstItem as alias)
        else
            return POSIX path of (container of firstItem as alias)
        end if
    else if (count of windows) > 0 then
        return POSIX path of (target of front window as alias)
    else
        return POSIX path of (desktop as alias)
    end if
end tell
' 2>/dev/null)

if [ -z "$TARGET_DIR" ]; then
    show_error "无法获取 Finder 当前目录"
    exit 1
fi

# 从剪贴板获取文件列表并复制到目标目录
RESULT=$(osascript -e '
use framework "AppKit"
set pb to current application'"'"'s NSPasteboard'"'"'s generalPasteboard()
set fileURLs to pb'"'"'s readObjectsForClasses:{current application'"'"'s NSURL} options:(missing value)
if fileURLs is missing value or (count of fileURLs) = 0 then
    return "NO_FILES"
end if
set paths to {}
repeat with u in fileURLs
    set end of paths to (u'"'"'s |path|()) as text
end repeat
set AppleScript'"'"'s text item delimiters to linefeed
return paths as text
' 2>/dev/null)

if [ "$RESULT" = "NO_FILES" ] || [ -z "$RESULT" ]; then
    show_error "剪贴板中没有文件"
    exit 1
fi

COUNT=0
FAIL=0
while IFS= read -r SRC; do
    [ -z "$SRC" ] && continue
    NAME=$(basename "$SRC")
    if cp -R "$SRC" "$TARGET_DIR/"; then
        ((COUNT++))
    else
        show_error "复制失败: $NAME"
        ((FAIL++))
    fi
done <<< "$RESULT"

if [ $COUNT -gt 0 ]; then
    show_success "已粘贴 $COUNT 个文件到 $TARGET_DIR"
fi
[ $FAIL -gt 0 ] && exit 1
exit 0
