#!/bin/bash

#
# 从最新的日志文件读取内容，并将其作为 Markdown 格式的消息发送。
#
# 重要: 假定执行此脚本的用户具有对 /var/log/wpn 目录的读取权限。
#       通常，这意味着脚本需要以 root 用户身份运行。
#
# 使用方法:
#   ./notification.sh <任务名称> <消息标题> <SENDKEY>
#

set -o pipefail

#
# 发送消息到方糖酱
#
# @param $1 消息标题
# @param $2 消息内容 (Markdown 格式)
# @param $3 方糖酱 SENDKEY
#
sc_send() {
    local text=$1
    local desp=$2
    local key=$3

    # 简单地对内容进行 URL 编码，以避免特殊字符问题
    desp=$(echo "$desp" | sed 's/&/%26/g; s/+/%2B/g; s/ /%20/g; s/\/%2F/g; s/?/%3F/g; s/#/%23/g; s/=/%3D/g')

    local postdata="text=$text&desp=$desp"
    local opts=(
        "--header" "Content-type: application/x-www-form-urlencoded"
        "--data" "$postdata"
    )

    local url
    if [[ "$key" =~ ^sctp([0-9]+)t ]]; then
        local num=${BASH_REMATCH[1]}
        url="https://${num}.push.ft07.com/send/${key}.send"
    else
        url="https://sctapi.ftqq.com/${key}.send"
    fi

    local result
    result=$(curl -X POST -s -o /dev/null -w "% {http_code}" "$url" "${opts[@]}")
    echo "$result"
}

main() {
  local task_name=$1
  local title=$2
  local key=$3

  local log_dir="/var/log/wpn"
  local SCRIPT_DIR
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
  
  # 引入日志记录器，以便此脚本自身也能记录日志
  source "${SCRIPT_DIR}/logger.sh"
  setup_logger "notification-task"
  
  if [ -z "$task_name" ] || [ -z "$title" ] || [ -z "$key" ]; then
    log_error "参数不足。用法: $0 <任务名称> <消息标题> <SENDKEY>"
    exit 1
  fi

  log_info "开始为任务 “${task_name}” 发送通知..."

  # 查找指定任务的最新日志文件
  local latest_log_file
  latest_log_file=$(find "$log_dir" -name "${task_name}-*.log" -type f -print0 | xargs -0 ls -t | head -n 1)

  if [ -z "$latest_log_file" ] || [ ! -f "$latest_log_file" ]; then
    local error_msg="找不到任务 “${task_name}” 的日志文件。"
    log_error "$error_msg"
    sc_send "$title" "$error_msg" "$key"
    exit 1
  fi
  
  log_info "找到最新日志文件: ${latest_log_file}"

  # 读取日志内容并格式化为 Markdown (每行后加一空行，以实现换行)
  # Markdown 中，行尾的两个空格可以强制换行
  local markdown_content
  markdown_content=$(awk '{printf "%s  \n\n", $0}' "$latest_log_file")

  if [ -z "$markdown_content" ]; then
      local warn_msg="日志文件为空: ${latest_log_file}"
      log_warn "$warn_msg"
      markdown_content="$warn_msg"
  fi

  log_info "准备发送通知内容..."

  local result
  result=$(sc_send "$title" "$markdown_content" "$key")
  
  log_info "通知发送完毕，HTTP 状态码: ${result}"
}

# 执行主函数，并传递所有脚本参数
main "$@"