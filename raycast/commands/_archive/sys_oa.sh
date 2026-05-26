#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.packageName OA 系统
# @raycast.title Open OA
# @raycast.description 启动并打开 OA 统一管理平台（Streamlit）
# @raycast.icon 🏢
# @raycast.mode fullOutput
source ~/Dev/tools/dev/lib/log_usage.sh

OA_DIR="$HOME/Dev/oa-project"
OA_URL="http://localhost:3000"
PORT=3000
MAX_WAIT=10
STREAMLIT="uv run --project $HOME/Dev/stations/web-stack/services/hydro-toolkit streamlit"

# 检查端口是否被占用
check_port() {
    lsof -i :$PORT -sTCP:LISTEN >/dev/null 2>&1
}

# 等待服务启动
wait_for_service() {
    local count=0
    while [ $count -lt $MAX_WAIT ]; do
        if check_port; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

# 检查 OA 是否已运行
if check_port; then
    echo "OA 已在运行，直接打开..."
    open "$OA_URL"
    exit 0
fi

# 检查目录是否存在
if [ ! -d "$OA_DIR" ]; then
    echo "❌ OA_DIR 未配置或路径不存在: $OA_DIR"
    echo ""
    echo "请编辑本脚本配置正确路径："
    echo "  文件: $0"
    echo "  第 12 行: OA_DIR=\"\$HOME/Dev/oa-project\"   ← 改为实际 OA 项目目录"
    echo "  第 16 行: STREAMLIT=\"... hydro-toolkit ...\"   ← hydro-toolkit 路径也已失效，请同步修正"
    exit 1
fi

# 检查 streamlit 项目目录是否存在（STREAMLIT 命令引用的 --project 路径）
STREAMLIT_PROJECT="$HOME/Dev/stations/web-stack/services/hydro-toolkit"
if [ ! -d "$STREAMLIT_PROJECT" ]; then
    echo "❌ Streamlit 运行环境项目不存在: $STREAMLIT_PROJECT"
    echo "   请编辑第 16 行 STREAMLIT 变量，指向有效的 uv project 目录"
    exit 1
fi

# 启动 OA 服务
echo "启动 OA 服务..."
cd "$OA_DIR" || exit 1

nohup "$STREAMLIT" run app.py --server.port $PORT > /tmp/oa.log 2>&1 &
OA_PID=$!

# 等待服务启动
if wait_for_service; then
    echo "OA 服务启动成功 (PID: $OA_PID)"
    open "$OA_URL"
else
    echo "错误：OA 服务启动超时，请检查日志 /tmp/oa.log"
    exit 1
fi
