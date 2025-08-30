#!/bin/bash

# 引入日志轮转工具函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log-rotation.sh" || {
  echo "错误：无法加载日志轮转工具函数"
  exit 1
}

# 创建轮转日志文件
LOG_FILE=$(create_rotation_log "dns-refresh") || {
  echo "错误：无法创建日志文件"
  exit 1
}

# 清理超过7天的旧日志文件
cleanup_old_logs "dns-refresh" 7

if [ "$EUID" -ne 0 ]; then
  echo "错误：此脚本需要 root 权限运行"
  echo "请使用：sudo $0"
  task_failure "DNS 刷新" "$LOG_FILE" "权限不足，需要 root 权限"
  exit 1
fi

# 开始任务
task_start "DNS 刷新" "$LOG_FILE"

# DNS 刷新操作成功标记
DNS_FLUSH_SUCCESS=false
FLUSH_METHODS_USED=""

# 尝试各种 DNS 刷新方法
log_message "$LOG_FILE" "尝试刷新 DNS 缓存..."

# 方法1: systemctl flush-dns
if systemctl flush-dns 2>/dev/null; then
  log_message "$LOG_FILE" "DNS 缓存已使用 systemctl flush-dns 清理"
  DNS_FLUSH_SUCCESS=true
  FLUSH_METHODS_USED="systemctl flush-dns"
else
  log_message "$LOG_FILE" "systemctl flush-dns 不可用，尝试其他方法..."
fi

# 方法2: systemd-resolve (如果第一种方法失败)
if [ "$DNS_FLUSH_SUCCESS" = "false" ] && command -v systemd-resolve >/dev/null 2>&1; then
  if systemd-resolve --flush-caches 2>/dev/null; then
    log_message "$LOG_FILE" "DNS 缓存已使用 systemd-resolve 清理"
    DNS_FLUSH_SUCCESS=true
    FLUSH_METHODS_USED="systemd-resolve"
  else
    log_message "$LOG_FILE" "systemd-resolve 命令执行失败"
  fi
fi

# 方法3: dns-clean (如果前面的方法都失败)
if [ "$DNS_FLUSH_SUCCESS" = "false" ] && [ -f /etc/init.d/dns-clean ]; then
  if /etc/init.d/dns-clean start 2>/dev/null; then
    log_message "$LOG_FILE" "DNS 缓存已使用 dns-clean 清理"
    DNS_FLUSH_SUCCESS=true
    FLUSH_METHODS_USED="dns-clean"
  else
    log_message "$LOG_FILE" "dns-clean 命令执行失败"
  fi
fi

# 方法4: 重启 systemd-resolved 服务
if [ "$DNS_FLUSH_SUCCESS" = "false" ]; then
  if systemctl restart systemd-resolved 2>/dev/null; then
    log_message "$LOG_FILE" "DNS 解析服务已通过 systemctl 重启"
    DNS_FLUSH_SUCCESS=true
    FLUSH_METHODS_USED="systemctl restart systemd-resolved"
  elif service systemd-resolved restart 2>/dev/null; then
    log_message "$LOG_FILE" "DNS 解析服务已通过 service 重启"
    DNS_FLUSH_SUCCESS=true
    FLUSH_METHODS_USED="service restart systemd-resolved"
  else
    log_message "$LOG_FILE" "无法重启 DNS 解析服务"
  fi
fi

# 方法5: nscd 缓存清理 (最后的备选方案)
if [ "$DNS_FLUSH_SUCCESS" = "false" ] && command -v nscd >/dev/null 2>&1; then
  if nscd -i hosts 2>/dev/null; then
    log_message "$LOG_FILE" "已使用 nscd 清理 DNS 缓存"
    DNS_FLUSH_SUCCESS=true
    FLUSH_METHODS_USED="nscd"
  else
    log_message "$LOG_FILE" "nscd 缓存清理也失败"
  fi
fi

# 记录当前 DNS 服务器配置
if [ -f /etc/resolv.conf ]; then
  log_message "$LOG_FILE" "当前 DNS 服务器配置："
  grep "nameserver" /etc/resolv.conf >> "$LOG_FILE" 2>/dev/null || {
    log_message "$LOG_FILE" "在 /etc/resolv.conf 中未找到 nameserver 配置"
  }
else
  log_message "$LOG_FILE" "警告：/etc/resolv.conf 文件不存在"
fi

# 收集DNS配置信息
dns_config=""
if [ -f /etc/resolv.conf ]; then
  current_dns=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | head -3)
  if [ -n "$current_dns" ]; then
    dns_config="当前 DNS 配置：
$current_dns"
  else
    dns_config="当前 DNS 配置：未找到 nameserver 配置"
  fi
else
  dns_config="当前 DNS 配置：/etc/resolv.conf 文件不存在"
fi

# 根据结果发送相应通知
if [ "$DNS_FLUSH_SUCCESS" = "true" ]; then
  success_details="DNS 缓存已成功刷新
使用方法：$FLUSH_METHODS_USED

$dns_config"
  task_success "DNS 刷新" "$LOG_FILE" "$success_details"
  echo "" >> "$LOG_FILE"
  exit 0
else
  failure_details="所有 DNS 刷新方法都失败了

尝试的方法：systemctl flush-dns, systemd-resolve, dns-clean, systemctl restart, nscd

$dns_config"
  task_failure "DNS 刷新" "$LOG_FILE" "$failure_details" 1
  echo "" >> "$LOG_FILE"
  exit 1
fi
