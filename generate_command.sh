#!/bin/bash

# 命令文件路径
COMMAND_FILE="/root/aztec_start_command.txt"

# 提示用户输入 aztec start 命令
echo "请输入 aztec start 命令（每行以 \\ 结尾，按 Ctrl+D 结束输入，或 Ctrl+C 退出）："

# 使用 while 循环读取多行输入，保留原始格式
aztec_command=""
while IFS= read -r line; do
    # 保留原始行内容（包括行尾的 \）
    aztec_command+="$line\n"
done

# 检查输入是否为空
if [[ -z "$aztec_command" ]]; then
    echo "错误：未输入命令！"
    exit 1
fi

# 将命令保存到文件，保留换行符
echo -n -e "$aztec_command" > "$COMMAND_FILE"

# 确认保存成功
if [[ $? -eq 0 ]]; then
    echo "命令已成功保存到 $COMMAND_FILE"
    cat "$COMMAND_FILE"
else
    echo "错误：保存命令失败！"
    exit 1
fi