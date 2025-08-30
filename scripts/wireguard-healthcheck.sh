#!/bin/bash

#
# WireGuard 组网健康自检脚本
#
# 检查 WireGuard 组网的各项健康指标，并将详细结果记录到日志中。
# 脚本执行完毕后，会读取完整的日志内容并发送通知。
#

set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# 引入日志记录器
source "${SCRIPT_DIR}/logger.sh"

# 引入通知脚本
source "${SCRIPT_DIR}/notification.sh"

#
# 主函数
#
main() {
  # 初始化日志文件，任务名称为 "wireguard-healthcheck"
  setup_logger "wireguard-healthcheck"

  # 权限检查
  if [ "$EUID" -ne 0 ]; then
    log_error "权限不足: 此脚本需要以 root 权限运行。请使用 'sudo' 执行。"
    exit 1
  fi

  log_info "========== 开始执行 WireGuard 健康检查 =========="

  # 1. WireGuard 服务状态检查
  log_info "--- 1. WireGuard 服务状态检查 ---"
  # 检查 WireGuard 内核模块
  if lsmod | grep -q wireguard; then
    log_info "[OK] WireGuard 内核模块: 已加载"
  else
    log_error "[ERROR] WireGuard 内核模块: 未加载"
  fi

  # 检查 wg-easy 容器状态
  if command -v docker &> /dev/null; then
    if docker ps --filter "name=wg-easy" --format "{{.Status}}" | grep -q "Up"; then
      local container_status
      container_status=$(docker ps --filter "name=wg-easy" --format "{{.Status}}" | head -1)
      log_info "[OK] wg-easy 容器: 运行中 ($container_status)"
    else
      if docker ps -a --filter "name=wg-easy" --format "{{.Status}}" | head -1 &> /dev/null; then
        local container_status
        container_status=$(docker ps -a --filter "name=wg-easy" --format "{{.Status}}" | head -1)
        log_error "[ERROR] wg-easy 容器: 未运行 ($container_status)"
      else
        log_error "[ERROR] wg-easy 容器: 容器不存在"
      fi
    fi
  else
    log_error "[ERROR] Docker 服务: Docker 未安装或不可用"
  fi

  # 2. 网络配置检查
  log_info "--- 2. 网络配置检查 ---"
  # 检查 WireGuard 接口
  if command -v wg &> /dev/null; then
    local wg_interfaces
    wg_interfaces=$(wg show interfaces 2>/dev/null)
    if [ -n "$wg_interfaces" ]; then
      local interface_count
      interface_count=$(echo "$wg_interfaces" | wc -w)
      log_info "[OK] WireGuard 接口: 发现 $interface_count 个接口: $wg_interfaces"
      
      for interface in $wg_interfaces; do
        local peer_count
        peer_count=$(wg show "$interface" peers 2>/dev/null | wc -l)
        log_info "[OK] 接口 $interface: 配置了 $peer_count 个客户端"
      done
    else
      log_warn "[WARN] WireGuard 接口: 未发现活动接口"
    fi
  else
    log_error "[ERROR] WireGuard 工具: wg 命令不可用"
  fi

  # 检查 IP 转发
  if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    log_info "[OK] IPv4 转发: 已启用"
  else
    log_error "[ERROR] IPv4 转发: 未启用"
  fi

  # 检查 WireGuard 端口监听
  local wireguard_ports=(31820)
  for port in "${wireguard_ports[@]}"; do
    if ss -ulnp | grep -q ":$port "; then
      local process_info
      process_info=$(ss -ulnp | grep ":$port " | awk '{print $6}' | head -1)
      log_info "[OK] WireGuard 端口 $port/UDP: 正在监听 ($process_info)"
    else
      log_warn "[WARN] WireGuard 端口 $port/UDP: 未在监听"
    fi
  done

  # 检查 Web UI 端口监听
  local web_ui_port=51821
  if ss -tlnp | grep -q ":$web_ui_port "; then
    log_info "[OK] Web UI 端口 $web_ui_port/TCP: 正在监听"
  else
    log_warn "[WARN] Web UI 端口 $web_ui_port/TCP: 未在监听"
  fi

  # 3. 系统资源检查
  log_info "--- 3. 系统资源检查 ---"
  # CPU 使用率
  local cpu_usage
  cpu_usage=$(top -bn1 | grep "^%Cpu" | awk '{print $2}' | cut -d'%' -f1)
  if [ -n "$cpu_usage" ]; then
    log_info "[INFO] CPU 使用率: ${cpu_usage}%"
  else
    log_warn "[WARN] CPU 使用率: 无法获取"
  fi

  # 内存使用率
  local memory_usage
  memory_usage=$(free | grep "^Mem:" | awk '{printf "%.0f", $3/$2 * 100.0}')
  if [ -n "$memory_usage" ]; then
    log_info "[INFO] 内存使用率: ${memory_usage}%"
  else
    log_warn "[WARN] 内存使用率: 无法获取"
  fi

  # 磁盘使用率
  local disk_usage
  disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
  if [ -n "$disk_usage" ]; then
    log_info "[INFO] 根分区使用率: ${disk_usage}%"
  else
    log_warn "[WARN] 根分区使用率: 无法获取"
  fi

  # 4. 安全检查
  log_info "--- 4. 安全检查 ---"
  # SSH 服务
  if systemctl is-active --quiet ssh.socket || systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    log_info "[OK] SSH 服务: 运行正常"
  else
    log_error "[ERROR] SSH 服务: 未运行"
  fi

  # fail2ban 服务
  if command -v fail2ban-client &> /dev/null; then
    if systemctl is-active --quiet fail2ban; then
      log_info "[OK] fail2ban 服务: 运行正常"
    else
      log_warn "[WARN] fail2ban 服务: 未运行"
    fi
  else
    log_warn "[WARN] fail2ban: 未安装"
  fi

  # 5. 连接统计
  log_info "--- 5. 连接统计 ---"
  if command -v wg &> /dev/null; then
    local total_peers=0
    local active_peers=0
    local five_minutes_ago
    five_minutes_ago=$(($(date +%s) - 300))

    for interface in $(wg show interfaces 2>/dev/null); do
      total_peers=$((total_peers + $(wg show "$interface" peers | wc -l)))
      
      # wg show <interface> dump | awk 'NR>1 { if ($5 > five_minutes_ago) active_peers++ }' five_minutes_ago="$five_minutes_ago"
      # The above awk is cleaner but let's stick to bash for simplicity
      while read -r line; do
        local latest_handshake
        latest_handshake=$(echo "$line" | awk '{print $5}')
        if [ "$latest_handshake" -gt "$five_minutes_ago" ]; then
          active_peers=$((active_peers + 1))
        fi
      done < <(wg show "$interface" dump | tail -n +2)

    done
    log_info "[INFO] 客户端统计: 总计 $total_peers 个, 5分钟内活跃 $active_peers 个"
  else
    log_warn "[WARN] 客户端统计: 无法统计 (wg 命令不可用)"
  fi

  log_info "========== WireGuard 健康检查执行完毕 =========="

  # 发送通知
  # 从 .env 文件加载 SENDKEY
  if [ -f "${SCRIPT_DIR}/../.env" ]; then
    set -a # 自动导出之后 source 的变量
    source "${SCRIPT_DIR}/../.env"
    set +a
  fi

  if [ -n "$SENDKEY" ]; then
    log_info "检测到 SENDKEY，准备发送通知..."
    # 调用 notification.sh 脚本
    # 注意: notification.sh 已经被当前脚本 source，可以直接调用其函数
    # 为了解耦和清晰，我们仍然可以作为命令调用它
    "${SCRIPT_DIR}/notification.sh" "wireguard-healthcheck" "WireGuard 健康检查报告" "$SENDKEY"
  else
    log_warn "未在 .env 文件中找到 SENDKEY，跳过发送通知。"
  fi
}

# 执行主函数
main
