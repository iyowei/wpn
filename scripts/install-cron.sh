#!/bin/bash

#
WPN 项目定时任务安装脚本
#
# 功能:
# - 安全地安装或更新项目的核心定时任务。
# - 使用唯一标识符管理任务，避免影响其他 cron jobs。
# - 自动处理脚本权限和 crontab 的备份与恢复。
#

set -o pipefail

# -- 配置 ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_DIR="/var/log/wpn"
CRON_TAG="# WPN-CRON-TASK"

# --- 脚本路径 ---
DNS_SCRIPT="${SCRIPT_DIR}/dns-refresh.sh"
REBOOT_SCRIPT="${SCRIPT_DIR}/server-reboot.sh"
HEALTHCHECK_SCRIPT="${SCRIPT_DIR}/wireguard-healthcheck.sh"

#
# 主函数
#
main() {
  echo "--- WPN 定时任务安装程序 ---"

  # 权限检查
  if [ "$EUID" -ne 0 ]; then
    echo "[错误] 此脚本需要以 root 权限运行。请使用: sudo $0"
    exit 1
  fi

  # 确保日志目录存在
  mkdir -p "$LOG_DIR"
  echo "[信息] 日志目录确保存在: $LOG_DIR"

  # 检查并设置脚本权限
  check_permissions

  # 清理旧任务
  cleanup_cron_tasks

  # 安装新任务
  install_cron_tasks

  # 最终确认和说明
  finalize
}

#
# 检查并设置所有相关脚本的可执行权限
#
check_permissions() {
  echo "[信息] 检查并设置脚本权限..."
  local scripts_to_check=(
    "$DNS_SCRIPT"
    "$REBOOT_SCRIPT"
    "$HEALTHCHECK_SCRIPT"
    "${SCRIPT_DIR}/logger.sh"
    "${SCRIPT_DIR}/notification.sh"
  )

  for script in "${scripts_to_check[@]}"; do
    if [ ! -f "$script" ]; then
      echo "[错误] 必需脚本不存在: $script"
      exit 1
    fi
    if [ ! -x "$script" ]; then
      chmod +x "$script"
      echo "    - 已为 $script 添加可执行权限。"
    fi
  done
}

#
# 清理之前由本脚本安装的定时任务
#
cleanup_cron_tasks() {
  echo "[信息] 正在清理旧的 WPN 定时任务..."
  local current_crontab
  current_crontab=$(crontab -l 2>/dev/null)

  if echo "$current_crontab" | grep -q "$CRON_TAG"; then
    # 使用 grep -v 和 -B 1 移除标识行及其前一行（任务行）
    # 但这不安全，因为任务行可能在标识行之后。
    # 更安全的方法是只移除包含 TAG 的行和相关的任务脚本行。
    echo "$current_crontab" | \
      grep -v "$CRON_TAG" | \
      grep -v "$DNS_SCRIPT" | \
      grep -v "$REBOOT_SCRIPT" | \
      grep -v "$HEALTHCHECK_SCRIPT" | \
      crontab -
    echo "[成功] 已清理旧的 WPN 定时任务。"
  else
    echo "[信息] 未发现需要清理的旧任务。"
  fi
}

#
# 将新任务添加到 crontab
#
install_cron_tasks() {
  echo "[信息] 正在安装新的 WPN 定时任务..."
  local backup_file="/tmp/crontab.bak.$(date +%s)"
  crontab -l > "$backup_file" 2>/dev/null
  echo "[信息] 当前 crontab 已备份到 $backup_file"

  # 使用子shell和管道将新任务附加到现有任务列表
  (
    crontab -l 2>/dev/null
    echo ""
    echo "$CRON_TAG: DNS 刷新任务 (每日 06:00)"
    echo "0 6 * * * TZ='Asia/Shanghai' $DNS_SCRIPT"
    echo ""
    echo "$CRON_TAG: 服务器重启任务 (每日 06:05)"
    echo "5 6 * * * TZ='Asia/Shanghai' $REBOOT_SCRIPT"
    echo ""
    echo "$CRON_TAG: WireGuard 健康检查任务 (每小时的 9-59 分钟)"
    echo "9-59 * * * * TZ='Asia/Shanghai' $HEALTHCHECK_SCRIPT"
    echo ""
  ) | crontab -

  if [ $? -ne 0 ]; then
    echo "[错误] 无法更新 crontab。正在从备份恢复..."
    crontab "$backup_file"
    exit 1
  fi

  echo "[成功] 定时任务已成功写入 crontab。"
}

#
# 完成安装，显示最终信息
#
finalize() {
  echo ""
  echo "--- 安装完成 ---"
  echo "已成功安装/更新 WPN 定时任务。"
  echo ""
  echo "当前相关任务列表:"
  crontab -l | grep "$CRON_TAG" -A 1
  echo ""
  echo "日志文件将存储在: ${LOG_DIR}/"
  echo "  - 例如: ${LOG_DIR}/wireguard-healthcheck-YYYYMMDD-HHMMSS.log"
  echo ""
  echo "请确保您的 .env 文件中已配置 SENDKEY 以接收任务通知。"
  echo "------------------"
}

# 执行主函数
main