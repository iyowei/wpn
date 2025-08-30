#!/bin/bash

#
# WPN 项目定时任务安装脚本
#
# 功能:
# - 安全地安装或更新项目的核心定时任务。
# - 通过持久化记录文件，精确地清理旧任务，避免重复。
# - 使用唯一标识符管理任务，避免影响其他 cron jobs。
# - 自动处理脚本权限和 crontab 的备份与恢复。
#

set -o pipefail

# --- 配置 ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
LOG_DIR="/var/log/wpn"
CRON_TAG="# WPN-CRON-TASK"
# 持久化存储上一次安装的脚本路径
PATHS_RECORD_FILE="/etc/wpn-cron.paths"

# --- 脚本路径 ---
DNS_SCRIPT="${SCRIPT_DIR}/dns-refresh.sh"
REBOOT_SCRIPT="${SCRIPT_DIR}/server-reboot.sh"
HEALTHCHECK_SCRIPT="${SCRIPT_DIR}/wireguard-healthcheck.sh"

#
# 主函数
#
main() {
  echo "--- WPN 定时任务安装程序 ---"

  if [ "$EUID" -ne 0 ]; then
    echo "[错误] 此脚本需要以 root 权限运行。请使用: sudo $0"
    exit 1
  fi

  mkdir -p "$LOG_DIR"
  echo "[信息] 日志目录确保存在: $LOG_DIR"

  check_permissions
  cleanup_cron_tasks
  install_cron_tasks
  finalize
}

#
# 检查并设置所有相关脚本的可执行权限
#
check_permissions() {
  echo "[信息] 检查并设置脚本权限..."
  local scripts_to_check=(
    "$DNS_SCRIPT" "$REBOOT_SCRIPT" "$HEALTHCHECK_SCRIPT"
    "${SCRIPT_DIR}/logger.sh" "${SCRIPT_DIR}/notification.sh"
  )
  for script in "${scripts_to_check[@]}"; do
    if [ ! -f "$script" ]; then
      echo "[错误] 必需脚本不存在: $script"; exit 1
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
  if [ -z "$current_crontab" ]; then
    echo "[信息] crontab 为空，无需清理。"
    return
  fi

  local cleaned_crontab="$current_crontab"

  # 首先，根据记录文件进行精确清理
  if [ -f "$PATHS_RECORD_FILE" ]; then
    echo "[信息] 发现安装记录，根据记录文件进行清理..."
    # 使用 grep -F -v -f file, 从 crontab 中移除记录文件里包含的所有行
    # -F: 将模式视为固定字符串 -v: 反转匹配 -f: 从文件获取模式
    cleaned_crontab=$(echo "$cleaned_crontab" | grep -F -v -f "$PATHS_RECORD_FILE")
  fi

  # 其次，清理 WPN 标识符，作为补充和兼容
  cleaned_crontab=$(echo "$cleaned_crontab" | grep -v "$CRON_TAG")

  # 最后，清理可能因各种原因残留的、未被记录的任务（作为兜底）
  cleaned_crontab=$(echo "$cleaned_crontab" | grep -v "dns-refresh.sh")
  cleaned_crontab=$(echo "$cleaned_crontab" | grep -v "server-reboot.sh")
  cleaned_crontab=$(echo "$cleaned_crontab" | grep -v "wireguard-healthcheck.sh")

  # 移除清理后可能产生的空行
  cleaned_crontab=$(echo "$cleaned_crontab" | awk 'NF')

  if [ "$cleaned_crontab" != "$current_crontab" ]; then
    echo "$cleaned_crontab" | crontab -
    echo "[成功] 已清理旧的 WPN 定时任务。"
  else
    echo "[信息] 未发现需要清理的旧任务。"
  fi
}

#
# 将新任务添加到 crontab 并更新记录文件
#
install_cron_tasks() {
  echo "[信息] 正在安装新的 WPN 定时任务..."
  local backup_file="/tmp/crontab.bak.$(date +%s)"
  crontab -l > "$backup_file" 2>/dev/null
  echo "[信息] 当前 crontab 已备份到 $backup_file"

  # 准备要写入记录文件的内容
  # 我们只记录脚本路径，因为这是清理的依据
  cat > "$PATHS_RECORD_FILE" <<- EOM
$DNS_SCRIPT
$REBOOT_SCRIPT
$HEALTHCHECK_SCRIPT
EOM

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
    rm -f "$PATHS_RECORD_FILE" # 安装失败，删除记录
    exit 1
  fi

  echo "[成功] 定时任务已成功写入 crontab。"
  echo "[成功] 本次安装的脚本路径已记录到 $PATHS_RECORD_FILE。"
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
  echo "请确保您的 .env 文件中已配置 SENDKEY 以接收任务通知。"
  echo "------------------"
}

# 执行主函数
main
