#!/bin/bash
# shellcheck disable=SC2034

#
# 通用日志记录器。
#
# 重要: 假定执行此脚本的用户具有对 /var/log/wpn 目录的写入权限。
#       通常，这意味着脚本需要以 root 用户身份运行。
#
# 使用方法:
#
#   1. 在你的主脚本中引入本文件:
#      SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
#      source "${SCRIPT_DIR}/logger.sh"
#
#   2. 在主脚本的开头调用 `setup_logger <任务名称>` 来初始化日志文件。
#
#   3. 使用日志函数记录消息:
#      log_info "这是一条信息。"
#      log_warn "这是一条警告。"
#      log_error "这是一条错误。"
#
#   `setup_logger` 函数会自动清理超过 7 天的旧日志。
#

LOG_DIR="/var/log/wpn"

#
# 设置当前任务的日志文件并清理旧日志
#
# @param $1 任务名称 (例如: "dns-refresh")
#
setup_logger() {
  local task_name=$1
  
  # 确保日志目录存在
  if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
  fi

  local timestamp
  timestamp=$(date '+%Y%m%d-%H%M%S')
  LOG_FILE="${LOG_DIR}/${task_name}-${timestamp}.log"
  export LOG_FILE

  # 创建日志文件
  touch "$LOG_FILE"

  # 清理 7 天前的旧日志
  find "$LOG_DIR" -name "${task_name}-*.log" -mtime +7 -exec rm {} \;
}

#
# 记录一条日志消息
#
# @param $1 日志级别 (例如: "INFO", "WARN", "ERROR")
# @param $2 日志消息
#
_log() {
  local level=$1
  local message=$2
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local log_entry="[${timestamp}] [${level}] ${message}"

  # 将日志条目同时打印到标准输出和追加到日志文件
  # tee -a: -a 表示追加内容
  echo "${log_entry}" | tee -a "$LOG_FILE"
}

#
# 记录信息级别的日志
#
# @param $1 消息
#
log_info() {
  _log "INFO" "$1"
}

#
# 记录警告级别的日志
#
# @param $1 消息
#
log_warn() {
  _log "WARN" "$1"
}

#
# 记录错误级别的日志
#
# @param $1 消息
#
log_error() {
  _log "ERROR" "$1"
}
