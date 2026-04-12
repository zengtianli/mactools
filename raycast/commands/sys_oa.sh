#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.packageName OA 系统
# @raycast.title 打开 OA
# @raycast.description 启动并打开 OA 统一管理平台（Streamlit）
# @raycast.icon 🏢
# @raycast.mode fullOutput

OA_DIR="$HOME/Dev/oa-project"
OA_URL="http://localhost:3000"
PORT=3000
MAX_WAIT=10
STREAMLIT="uv run --project $HOME/Dev/hydro-toolkit streamlit"

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
    echo "错误：OA 目录不存在 ($OA_DIR)"
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
