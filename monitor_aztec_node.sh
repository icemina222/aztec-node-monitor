#!/bin/bash

# 日志文件
LOG_FILE="/root/aztec_node_monitor.log"

# 命令文件路径
COMMAND_FILE="/root/aztec_start_command.txt"

# tmux 会话名称
TMUX_SESSION="session-Aztec"

# 终止所有现有脚本实例
SCRIPT_NAME=$(basename "$0")
CURRENT_PID=$$
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminating any existing $SCRIPT_NAME instances..." >> "$LOG_FILE"
pkill -f "$SCRIPT_NAME" 2>>"$LOG_FILE"
if [[ $? -eq 0 ]]; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminated existing $SCRIPT_NAME instances" >> "$LOG_FILE"
else
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - No existing $SCRIPT_NAME instances found or failed to terminate" >> "$LOG_FILE"
fi
# 等待片刻确保旧实例终止
sleep 2
# 检查当前脚本是否仍在运行
if ! ps -p "$CURRENT_PID" > /dev/null; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Current script (PID: $CURRENT_PID) was terminated, exiting..." >> "$LOG_FILE"
    exit 1
fi
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Starting $SCRIPT_NAME (single instance, PID: $CURRENT_PID)" >> "$LOG_FILE"

# 检查节点状态的函数
check_node_status() {
    local result
    result=$(curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
        http://localhost:8080 | jq -r ".result.proven.number")
    
    # 检查结果是否为纯数字
    if [[ $result =~ ^[0-9]+$ ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node is running normally (L2Tips: $result)" >> "$LOG_FILE"
        return 0  # 节点正常
    else
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node check failed (Result: $result)" >> "$LOG_FILE"
        return 1  # 节点异常
    fi
}

# 清理 aztec 进程和 session-Aztec 会话
cleanup_aztec() {
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Cleaning up existing Aztec processes and tmux session..." >> "$LOG_FILE"
    
    # 终止所有可能的 aztec 进程
    pkill -f "aztec start" 2>>"$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminated existing Aztec processes" >> "$LOG_FILE"
    fi

    # 仅终止 session-Aztec
    tmux has-session -t "$TMUX_SESSION" 2>>"$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        tmux kill-session -t "$TMUX_SESSION" 2>>"$LOG_FILE"
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminated tmux session: $TMUX_SESSION" >> "$LOG_FILE"
    fi
}

# 重启节点的函数
restart_node() {
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Attempting to restart node..." >> "$LOG_FILE"
    
    # 检查命令文件是否存在
    if [[ ! -f "$COMMAND_FILE" ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Command file $COMMAND_FILE not found!" >> "$LOG_FILE"
        return 1
    fi

    # 读取命令
    local command
    command=$(cat "$COMMAND_FILE")

    # 清理现有 aztec 进程和 tmux 会话
    cleanup_aztec

    # 创建新的 tmux 会话并执行命令
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Creating new tmux session $TMUX_SESSION" >> "$LOG_FILE"
    tmux new-session -d -s "$TMUX_SESSION" 2>>"$LOG_FILE"
    if [[ $? -ne 0 ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Failed to create tmux session $TMUX_SESSION" >> "$LOG_FILE"
        return 1
    fi
    tmux send-keys -t "$TMUX_SESSION" "$command" Enter 2>>"$LOG_FILE"
    if [[ $? -ne 0 ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Failed to send command to tmux session $TMUX_SESSION" >> "$LOG_FILE"
        return 1
    fi
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node restart command sent: $command" >> "$LOG_FILE"
}

# 主循环
while true; do
    # 获取当前 UTC 时间的分钟数和秒数
    current_minute=$(date -u +%M)
    current_second=$(date -u +%S)

    # 检查是否为整点或半点（00 或 30 分）
    if [[ $current_minute == "00" || $current_minute == "30" ]] && [[ $current_second == "00" ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Starting node status check..." >> "$LOG_FILE"

        # 第一次检查
        if ! check_node_status; then
            # 如果第一次检查失败，连续 5 分钟每分钟检查
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node check failed, starting 5-minute verification..." >> "$LOG_FILE"
            failure_count=0
            for ((i=1; i<=5; i++)); do
                sleep 60
                if ! check_node_status; then
                    ((failure_count++))
                else
                    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node recovered during verification (L2Tips: $(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r ".result.proven.number"))" >> "$LOG_FILE"
                    break
                fi
            done

            # 如果 5 次检查都失败，重启节点
            if [[ $failure_count -eq 5 ]]; then
                echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node failed 5 consecutive checks, restarting..." >> "$LOG_FILE"
                restart_node
                # 重启后等待 30 分钟
                echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Waiting 30 minutes before next check..." >> "$LOG_FILE"
                sleep 1800
            fi
        fi
    fi

    # 每秒检查一次，避免高 CPU 占用
    sleep 1
done