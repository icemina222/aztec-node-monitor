#!/bin/bash

# 命令文件路径
COMMAND_FILE="/root/aztec_start_command.txt"

# 提示用户输入 aztec start 命令
echo "请输入 aztec start 命令（例如：aztec start --node --archiver ...）："
read -r aztec_command

# 检查输入是否为空
if [[ -z "$aztec_command" ]]; then
    echo "错误：未输入命令！"
    exit 1
fi

# 将输入的命令保存到文件
echo "$aztec_command" > "$COMMAND_FILE"

# 确认保存成功
if [[ $? -eq 0 ]]; then
    echo "命令已成功保存到 $COMMAND_FILE"
    cat "$COMMAND_FILE"
else
    echo "错误：保存命令失败！"
    exit 1
fi