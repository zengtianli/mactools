#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Cleanup Downloads
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🧹
# @raycast.packageName File Utils
# @raycast.description Auto cleanup: organize by type → AI rename → project sort

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PYTHON=$(which python3)
SCRIPTS="$REPO_ROOT/scripts/file"

source ~/.zshrc 2>/dev/null

echo "=== Step 1: 按扩展名分类 ==="
$PYTHON "$SCRIPTS/downloads_organizer.py" --scan-archive
if [ $? -ne 0 ]; then
    echo "❌ Step 1 失败，中止"
    exit 1
fi

echo ""
echo "=== Step 2: AI 分析 + 重命名 ==="
$PYTHON "$SCRIPTS/smart_rename.py" analyze --all
if [ $? -ne 0 ]; then
    echo "❌ Step 2 analyze 失败，中止"
    exit 1
fi

$PYTHON "$SCRIPTS/smart_rename.py" execute
if [ $? -ne 0 ]; then
    echo "❌ Step 2 execute 失败，可用 smart_rename.py rollback 回滚"
    exit 1
fi

echo ""
echo "=== Step 3: 按项目归组 ==="
$PYTHON "$SCRIPTS/project_sort.py"

echo ""
echo "========================================="
echo "✅ Downloads 清理完成"
echo "回滚重命名: smart_rename.py rollback"
echo "========================================="
