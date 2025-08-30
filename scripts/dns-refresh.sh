#!/bin/bash

#
# DNS 缓存刷新脚本
#
# 依次尝试多种方法刷新系统的 DNS 缓存，记录过程和结果。
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
  setup_logger "dns-refresh"

  # 权限检查
  if [ "$EUID" -ne 0 ]; then
    log_error "权限不足: 此脚本需要以 root 权限运行。请使用 'sudo' 执行。"
    exit 1
  fi

  log_info "========== 开始执行 DNS 缓存刷新任务 =========="

  # 尝试各种 DNS 刷新方法
  log_info "尝试刷新 DNS 缓存..."

  # 方法1: systemd-resolve
  if command -v systemd-resolve &> /dev/null; then
    if systemd-resolve --flush-caches; then
      log_info "[成功] DNS 缓存已通过 'systemd-resolve --flush-caches' 清理。"
      post_check
      send_notification
      exit 0
    fi
  fi

  # 方法2: 重启 systemd-resolved 服务
  if systemctl is-active --quiet systemd-resolved; then
    if systemctl restart systemd-resolved; then
      log_info "[成功] DNS 缓存已通过重启 'systemd-resolved' 服务清理。"
      post_check
      send_notification
      exit 0
    fi
  fi

  # 方法3: nscd (如果不常用，作为备选)
  if command -v nscd &> /dev/null; then
    if nscd -i hosts; then
      log_info "[成功] DNS 缓存已通过 'nscd -i hosts' 清理。"
      post_check
      send_notification
      exit 0
    fi
  fi

  # 如果所有方法都失败了
  log_error "[失败] 所有 DNS 缓存刷新方法均告失败。"
  post_check
  send_notification
  exit 1
}

#
# 记录当前 DNS 配置作为参考
#
post_check() {
  log_info "--- 当前 DNS 服务器配置 ---"
  if [ -f /etc/resolv.conf ]; then
    # 使用 awk 添加前缀，使其更清晰
    awk '{print "[CONFIG] " $0}' /etc/resolv.conf
  else
    log_warn "[WARN] /etc/resolv.conf 文件不存在。"
  fi
  log_info "======================================"
}

#
# 发送通知
#
send_notification() {
  log_info "刷新任务执行完毕，准备发送通知..."
  # 从 .env 文件加载 SENDKEY
  if [ -f "${SCRIPT_DIR}/../.env" ]; then
    set -a
    source "${SCRIPT_DIR}/../.env"
    set +a
  fi

  if [ -n "$SENDKEY" ]; then
    "${SCRIPT_DIR}/notification.sh" "dns-refresh" "DNS 缓存刷新报告" "$SENDKEY"
  else
    log_warn "未在 .env 文件中找到 SENDKEY，跳过发送通知。"
  fi
}

# 执行主函数
main