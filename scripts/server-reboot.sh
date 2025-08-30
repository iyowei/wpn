#!/bin/bash

#
# 服务器计划重启脚本
#
# 在重启前记录系统状态，发送通知，然后执行重启操作。
#

set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# 引入日志记录器
source "${SCRIPT_DIR}/logger.sh"

#
# 主函数
#
main() {
  # 初始化日志
  setup_logger "server-reboot"

  # 权限检查
  if [ "$EUID" -ne 0 ]; then
    log_error "权限不足: 此脚本需要以 root 权限运行。请使用 'sudo' 执行。"
    # 尝试发送通知
    send_notification "failure"
    exit 1
  fi

  log_info "========== 服务器计划重启任务开始 =========="
  log_info "将在 60 秒后重启服务器..."

  # 记录重启前的系统状态
  log_info "--- 重启前系统状态 ---"
  log_info "系统运行时间: $(uptime)"
  log_info "内存使用情况:"
  free -h | awk '{print "  " $0}'
  log_info "根分区磁盘使用情况:"
  df -h / | awk '{print "  " $0}'
  
  if command -v docker &> /dev/null; then
    log_info "当前运行的 Docker 容器:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | awk '{print "  " $0}'
  fi
  log_info "------------------------"

  # 发送重启通知
  send_notification "success"

  log_info "同步文件系统缓存到磁盘..."
  sync
  sync

  log_info "准备执行重启..."

  # 等待几秒，确保日志和通知有机会完成
  sleep 5

  # 执行重启
  # 使用 shutdown 命令，并给用户留出取消的时间
  shutdown -r +1 "服务器将在一分钟后按计划重启。"

  log_info "重启命令已发出。"
}

#
# 发送通知
#
send_notification() {
  local status=$1
  local title="服务器计划重启通知"

  if [ "$status" = "failure" ]; then
      title="服务器重启失败通知"
  fi

  log_info "准备发送通知..."
  # 从 .env 文件加载 SENDKEY
  if [ -f "${SCRIPT_DIR}/../.env" ]; then
    set -a
    source "${SCRIPT_DIR}/../.env"
    set +a
  fi

  if [ -n "$SENDKEY" ]; then
    "${SCRIPT_DIR}/notification.sh" "server-reboot" "$title" "$SENDKEY"
  else
    log_warn "未在 .env 文件中找到 SENDKEY，跳过发送通知。"
  fi
}

# 执行主函数
main