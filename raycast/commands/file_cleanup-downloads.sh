#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Cleanup Downloads
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🧹
# @raycast.packageName File Utils
# @raycast.description Auto cleanup: organize by type → AI rename → project sort

source "$(dirname "$(realpath "$0")")/../lib/run_python.sh"

# run_python uses exec, so we define a non-exec variant for multi-step scripts
_uv_python() { local s="$1"; shift; uv run --project "$PROJECT_ROOT" python3 "$SCRIPTS_DIR/$s" "$@"; }

echo "=== Step 1: 按扩展名分类 ==="
_uv_python "file/downloads_organizer.py" --scan-archive
if [ $? -ne 0 ]; then
    echo "❌ Step 1 失败，中止"
    exit 1
fi

echo ""
echo "=== Step 2: AI 分析 + 重命名 ==="
_uv_python "file/smart_rename.py" analyze --all
if [ $? -ne 0 ]; then
    echo "❌ Step 2 analyze 失败，中止"
    exit 1
fi

_uv_python "file/smart_rename.py" execute
if [ $? -ne 0 ]; then
    echo "❌ Step 2 execute 失败，可用 smart_rename.py rollback 回滚"
    exit 1
fi

echo ""
echo "=== Step 3: 按项目归组 ==="
_uv_python "file/project_sort.py"

echo ""
echo "========================================="
echo "✅ Downloads 清理完成"
echo "回滚重命名: smart_rename.py rollback"
echo "========================================="
