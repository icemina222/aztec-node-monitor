#!/bin/bash

# 9.20 v1

# 日志文件
LOG_FILE="/root/aztec_node_monitor.log"

# 命令文件路径
COMMAND_FILE="/root/aztec_start_command.txt"

# tmux 会话名称
TMUX_SESSION="session-Aztec"

# 清空日志文件以避免混淆
> "$LOG_FILE"

# 终止所有现有脚本实例（排除当前脚本）
SCRIPT_NAME=$(basename "$0")
CURRENT_PID=$$
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Checking for existing $SCRIPT_NAME instances..." >> "$LOG_FILE"
# 记录当前进程列表以便调试
ps aux | grep "$SCRIPT_NAME" | grep -v grep >> "$LOG_FILE"
# 使用 pgrep -f 查找进程，并通过 /proc/<pid>/cmdline 确认是脚本本身
RUNNING_PIDS=""
for pid in $(pgrep -f "$SCRIPT_NAME"); do
    if [[ $pid != $CURRENT_PID ]]; then
        # 检查 /proc/<pid>/cmdline 是否包含脚本路径
        if [[ -f "/proc/$pid/cmdline" && $(cat "/proc/$pid/cmdline" | tr '\0' '\n' | grep -c "$SCRIPT_NAME") -gt 0 ]]; then
            RUNNING_PIDS="$RUNNING_PIDS $pid"
        fi
    fi
done
if [[ -n "$RUNNING_PIDS" ]]; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminating existing $SCRIPT_NAME instances (PIDs:$RUNNING_PIDS)..." >> "$LOG_FILE"
    echo "$RUNNING_PIDS" | xargs -r kill -9 2>>"$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminated existing $SCRIPT_NAME instances" >> "$LOG_FILE"
    else
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Failed to terminate existing $SCRIPT_NAME instances" >> "$LOG_FILE"
    fi
    # 多次尝试终止，确保清理干净
    sleep 5
    RUNNING_PIDS=""
    for pid in $(pgrep -f "$SCRIPT_NAME"); do
        if [[ $pid != $CURRENT_PID ]]; then
            if [[ -f "/proc/$pid/cmdline" && $(cat "/proc/$pid/cmdline" | tr '\0' '\n' | grep -c "$SCRIPT_NAME") -gt 0 ]]; then
                RUNNING_PIDS="$RUNNING_PIDS $pid"
            fi
        fi
    done
    if [[ -n "$RUNNING_PIDS" ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Retrying to terminate residual $SCRIPT_NAME instances (PIDs:$RUNNING_PIDS)..." >> "$LOG_FILE"
        echo "$RUNNING_PIDS" | xargs -r kill -9 2>>"$LOG_FILE"
        if [[ $? -eq 0 ]]; then
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminated residual $SCRIPT_NAME instances" >> "$LOG_FILE"
        else
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Failed to terminate residual $SCRIPT_NAME instances" >> "$LOG_FILE"
        fi
    fi
else
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - No existing $SCRIPT_NAME instances found" >> "$LOG_FILE"
fi
# 最后检查残留实例
sleep 5
RUNNING_PIDS=$(pgrep -f "$SCRIPT_NAME" | grep -v "$CURRENT_PID")
if [[ -n "$RUNNING_PIDS" ]]; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Warning: Residual $SCRIPT_NAME instances still running (PIDs:$RUNNING_PIDS)" >> "$LOG_FILE"
    ps aux | grep "$SCRIPT_NAME" | grep -v grep >> "$LOG_FILE"
else
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - No residual $SCRIPT_NAME instances found" >> "$LOG_FILE"
fi
# 检查当前脚本是否仍在运行
if ! ps -p "$CURRENT_PID" > /dev/null; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Current script (PID: $CURRENT_PID) was terminated, exiting..." >> "$LOG_FILE"
    exit 1
fi
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Starting $SCRIPT_NAME (single instance, PID: $CURRENT_PID)" >> "$LOG_FILE"

# 检查节点状态的函数
check_node_status() {
    local result
    # 添加超时避免脚本卡住
    result=$(timeout 30 curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
        http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null)
    
    # 检查结果是否为纯数字
    if [[ $result =~ ^[0-9]+$ ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node is running normally (L2Tips: $result)" >> "$LOG_FILE"
        return 0  # 节点正常
    else
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node check failed (Result: $result)" >> "$LOG_FILE"
        return 1  # 节点异常
    fi
}

# 清理 aztec 进程、tmux 会话和 Docker 容器（改进版 - 只优化容器清理）
cleanup_aztec() {
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Cleaning up existing Aztec processes, tmux session, and Docker containers..." >> "$LOG_FILE"
    
    # 使用优化的方式删除所有aztec开头的容器
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Cleaning up all Aztec Docker containers..." >> "$LOG_FILE"
    
    # 获取所有aztec开头的容器ID
    AZTEC_CONTAINERS=$(docker ps -aq | xargs -I {} sh -c 'docker inspect --format="{{.Name}} {}" {} 2>/dev/null' | grep "^/aztec" | awk '{print $2}' 2>/dev/null)
    
    if [[ -n "$AZTEC_CONTAINERS" ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Found Aztec containers: $AZTEC_CONTAINERS" >> "$LOG_FILE"
        echo "$AZTEC_CONTAINERS" | xargs docker rm -f 2>>"$LOG_FILE"
        if [[ $? -eq 0 ]]; then
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Successfully removed Aztec containers: $AZTEC_CONTAINERS" >> "$LOG_FILE"
        else
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Warning: Some containers may have failed to remove" >> "$LOG_FILE"
        fi
    else
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - No Aztec containers found" >> "$LOG_FILE"
    fi
    
    # 作为备用，也清理可能遗漏的容器（保留原有逻辑作为双重保险）
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Double-checking for any remaining Aztec containers..." >> "$LOG_FILE"
    REMAINING_CONTAINERS=$(docker ps -aq --filter ancestor=aztecprotocol/aztec 2>/dev/null)
    if [[ -n "$REMAINING_CONTAINERS" ]]; then
        docker rm -f $REMAINING_CONTAINERS 2>>"$LOG_FILE"
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Cleaned up remaining containers: $REMAINING_CONTAINERS" >> "$LOG_FILE"
    fi
    
    # 终止所有可能的 aztec 进程
    pkill -f "aztec start" 2>>"$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminated existing Aztec processes" >> "$LOG_FILE"
    else
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - No Aztec processes found or failed to terminate" >> "$LOG_FILE"
    fi

    # 仅终止 session-Aztec
    tmux has-session -t "$TMUX_SESSION" 2>>"$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        tmux kill-session -t "$TMUX_SESSION" 2>>"$LOG_FILE"
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Terminated tmux session: $TMUX_SESSION" >> "$LOG_FILE"
    else
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - No tmux session $TMUX_SESSION found" >> "$LOG_FILE"
    fi
}

# 重启节点的函数（保持原有时间间隔）
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

    # 清理现有 aztec 进程、tmux 会话和 Docker 容器
    cleanup_aztec

    # 强制清理tmux服务器，解决"server exited unexpectedly"问题
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Cleaning up tmux server..." >> "$LOG_FILE"
    
    # 杀死所有tmux进程
    pkill -f tmux 2>>"$LOG_FILE" || true
    
    # 强制杀死tmux服务器
    tmux kill-server 2>>"$LOG_FILE" || true
    
    # 清理所有tmux相关的socket文件和目录
    rm -rf /tmp/tmux-* 2>>"$LOG_FILE" || true
    
    # 清理可能的其他socket位置
    rm -rf /var/run/tmux-* 2>>"$LOG_FILE" || true
    
    # 等待确保清理完成
    sleep 3

    # 创建新的 tmux 会话并执行命令，增加重试机制
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Creating new tmux session $TMUX_SESSION" >> "$LOG_FILE"
    
    # 最多重试3次创建tmux会话
    for ((retry=1; retry<=3; retry++)); do
        tmux new-session -d -s "$TMUX_SESSION" 2>>"$LOG_FILE"
        if [[ $? -eq 0 ]]; then
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Successfully created tmux session $TMUX_SESSION (attempt $retry)" >> "$LOG_FILE"
            break
        else
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Failed to create tmux session $TMUX_SESSION (attempt $retry)" >> "$LOG_FILE"
            if [[ $retry -lt 3 ]]; then
                # 再次清理并等待
                tmux kill-server 2>>"$LOG_FILE" || true
                rm -rf /tmp/tmux-* 2>>"$LOG_FILE" || true
                sleep 3
            else
                echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Failed to create tmux session after 3 attempts" >> "$LOG_FILE"
                return 1
            fi
        fi
    done
    
    # 发送命令到tmux会话
    tmux send-keys -t "$TMUX_SESSION" "$command" Enter 2>>"$LOG_FILE"
    if [[ $? -ne 0 ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Failed to send command to tmux session $TMUX_SESSION" >> "$LOG_FILE"
        return 1
    fi
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node restart command sent: $command" >> "$LOG_FILE"
    
    # 等待节点服务启动并验证（保持原有的5分钟）
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Waiting for node service to start..." >> "$LOG_FILE"
    
    # 等待最多5分钟让节点完全启动
    for ((wait_time=0; wait_time<=300; wait_time+=15)); do
        sleep 15
        # 尝试检查节点状态
        local health_check
        health_check=$(timeout 15 curl -s -X POST -H 'Content-Type: application/json' \
           -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
           http://localhost:8080 2>/dev/null | jq -r ".result.proven.number" 2>/dev/null)
        
        if [[ $health_check =~ ^[0-9]+$ ]]; then
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node service is responding normally (L2Tips: $health_check, after ${wait_time}s)" >> "$LOG_FILE"
            return 0
        elif [[ -n "$health_check" && "$health_check" != "null" ]]; then
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node service responding but not ready yet (Response: $health_check, after ${wait_time}s)" >> "$LOG_FILE"
        else
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Still waiting for node service... (${wait_time}s)" >> "$LOG_FILE"
        fi
        
        # 检查节点进程是否还在运行
        if ! pgrep -f "aztec start" > /dev/null; then
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Error: Aztec process has stopped unexpectedly" >> "$LOG_FILE"
            return 1
        fi
    done
    
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Warning: Node service did not respond within 5 minutes, but process is still running" >> "$LOG_FILE"
    
    # 即使超时，如果进程还在运行，也不算完全失败
    if pgrep -f "aztec start" > /dev/null; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Aztec process is still running, restart may be successful" >> "$LOG_FILE"
        return 0
    else
        return 1
    fi
}

# 主循环
while true; do
    # 获取当前 UTC 时间
    current_minute=$(date -u +%M)
    current_second=$(date -u +%S)

    # 检查是否为每10分钟的检测时间点（00, 10, 20, 30, 40, 50分）
    if [[ $current_minute =~ ^(00|10|20|30|40|50)$ ]] && [[ $current_second == "00" ]]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Starting scheduled node status check..." >> "$LOG_FILE"

        # 第一次检查
        if ! check_node_status; then
            # 如果第一次检查失败，每30秒检查一次，连续检查3次
            echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node check failed, starting 30-second interval verification..." >> "$LOG_FILE"
            failure_count=1  # 第一次已经失败了
            
            for ((i=1; i<=2; i++)); do  # 只需要再检查2次，总共3次
                sleep 30
                if ! check_node_status; then
                    ((failure_count++))
                else
                    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node recovered during verification" >> "$LOG_FILE"
                    break
                fi
            done

            # 如果连续3次检查都失败，重启节点
            if [[ $failure_count -eq 3 ]]; then
                echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Node failed 3 consecutive checks, restarting..." >> "$LOG_FILE"
                restart_node
            fi
        fi
    fi

    # 每秒检查一次时间，避免高 CPU 占用
    sleep 1
done