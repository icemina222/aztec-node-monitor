#!/bin/bash

# 命令文件路径
COMMAND_FILE="/root/aztec_start_command.txt"

# 提示用户输入 aztec start 命令
echo "请输入 aztec start 命令（每行以 \ 结尾，最后一行不需要，按 Ctrl+D 结束输入，或 Ctrl+C 退出）："

# 使用数组存储多行输入
lines=()
while IFS= read -r line; do
    lines+=("$line")
done

# 检查输入是否为空
if [[ ${#lines[@]} -eq 0 ]]; then
    echo "错误：未输入命令！"
    exit 1
fi

# 将多行命令保存到文件，保留原始格式
> "$COMMAND_FILE"  # 清空文件
for ((i=0; i<${#lines[@]}; i++)); do
    # 如果不是最后一行，保留行尾的 \，否则直接写入
    if [[ $i -lt $((${#lines[@]}-1)) ]]; then
        echo "${lines[i]}" >> "$COMMAND_FILE"
    else
        # 最后一行去除尾部 \（如果有）
        echo "${lines[i]}" | sed 's/\\$//' >> "$COMMAND_FILE"
    fi
done

# 确认保存成功
if [[ $? -eq 0 ]]; then
    echo "命令已成功保存到 $COMMAND_FILE"
    cat "$COMMAND_FILE"
else
    echo "错误：保存命令失败！"
    exit 1
fi