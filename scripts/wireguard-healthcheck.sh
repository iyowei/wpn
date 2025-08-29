#!/bin/bash

# WireGuard 组网健康自检脚本
# 每小时执行一次，检查 WireGuard 组网的各项健康指标

# 引入日志轮转工具函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log-rotation.sh" || {
  echo "错误：无法加载日志轮转工具函数"
  exit 1
}

# 创建轮转日志文件
LOG_FILE=$(create_rotation_log "wireguard-healthcheck") || {
  echo "错误：无法创建日志文件"
  exit 1
}

# 清理超过7天的旧日志文件
cleanup_old_logs "wireguard-healthcheck" 7

# 权限检查
if [ "$EUID" -ne 0 ]; then
  echo "错误：此脚本需要 root 权限运行"
  echo "请使用：sudo $0"
  task_failure "WireGuard 健康检查" "$LOG_FILE" "权限不足，需要 root 权限"
  exit 1
fi

# 开始任务
task_start "WireGuard 健康检查" "$LOG_FILE"

# 健康检查结果统计
CHECK_COUNT=0
SUCCESS_COUNT=0
WARNING_COUNT=0
ERROR_COUNT=0
HEALTH_DETAILS=""

# 添加检查结果函数
add_check_result() {
  local item="$1"
  local status="$2"  # "SUCCESS", "WARNING", "ERROR"
  local message="$3"
  
  CHECK_COUNT=$((CHECK_COUNT + 1))
  
  case "$status" in
    "SUCCESS")
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      log_message "$LOG_FILE" "✅ $item: $message"
      HEALTH_DETAILS="$HEALTH_DETAILS✅ $item: $message\n"
      ;;
    "WARNING")
      WARNING_COUNT=$((WARNING_COUNT + 1))
      log_message "$LOG_FILE" "⚠️  $item: $message"
      HEALTH_DETAILS="$HEALTH_DETAILS⚠️  $item: $message\n"
      ;;
    "ERROR")
      ERROR_COUNT=$((ERROR_COUNT + 1))
      log_message "$LOG_FILE" "❌ $item: $message"
      HEALTH_DETAILS="$HEALTH_DETAILS❌ $item: $message\n"
      ;;
  esac
}

# 1. WireGuard 服务状态检查
log_message "$LOG_FILE" "开始 WireGuard 服务状态检查..."

# 检查 WireGuard 内核模块
if lsmod | grep -q wireguard; then
  add_check_result "WireGuard 内核模块" "SUCCESS" "已加载"
else
  add_check_result "WireGuard 内核模块" "ERROR" "未加载"
fi

# 检查 wg-easy 容器状态
if command -v docker >/dev/null 2>&1; then
  if docker ps --filter "name=wg-easy" --format "{{.Status}}" | grep -q "Up"; then
    container_status=$(docker ps --filter "name=wg-easy" --format "{{.Status}}" | head -1)
    add_check_result "wg-easy 容器" "SUCCESS" "运行中 ($container_status)"
  else
    if docker ps -a --filter "name=wg-easy" --format "{{.Status}}" | head -1 >/dev/null 2>&1; then
      container_status=$(docker ps -a --filter "name=wg-easy" --format "{{.Status}}" | head -1)
      add_check_result "wg-easy 容器" "ERROR" "未运行 ($container_status)"
    else
      add_check_result "wg-easy 容器" "ERROR" "容器不存在"
    fi
  fi
else
  add_check_result "Docker 服务" "ERROR" "Docker 未安装或不可用"
fi

# 2. 网络配置检查
log_message "$LOG_FILE" "开始网络配置检查..."

# 检查 WireGuard 接口
if command -v wg >/dev/null 2>&1; then
  wg_interfaces=$(wg show interfaces 2>/dev/null)
  if [ -n "$wg_interfaces" ]; then
    interface_count=$(echo "$wg_interfaces" | wc -w)
    add_check_result "WireGuard 接口" "SUCCESS" "发现 $interface_count 个接口: $wg_interfaces"
    
    # 检查每个接口的详细信息
    for interface in $wg_interfaces; do
      peer_count=$(wg show "$interface" peers 2>/dev/null | wc -l)
      add_check_result "接口 $interface" "SUCCESS" "配置了 $peer_count 个客户端"
    done
  else
    add_check_result "WireGuard 接口" "WARNING" "未发现活动接口"
  fi
else
  add_check_result "WireGuard 工具" "ERROR" "wg 命令不可用"
fi

# 检查 IP 转发
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
  add_check_result "IPv4 转发" "SUCCESS" "已启用"
else
  add_check_result "IPv4 转发" "ERROR" "未启用"
fi

# 检查端口监听状态
wireguard_ports=(31820 31821)
for port in "${wireguard_ports[@]}"; do
  # 优先使用 ss，如果不可用则使用 netstat
  if command -v ss >/dev/null 2>&1; then
    if ss -ulnp | grep -q ":$port "; then
      process_info=$(ss -ulnp | grep ":$port " | awk '{print $6}' | head -1)
      add_check_result "端口 $port UDP" "SUCCESS" "正在监听 ($process_info)"
    else
      add_check_result "端口 $port UDP" "WARNING" "未在监听"
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -ulnp 2>/dev/null | grep -q ":$port "; then
      add_check_result "端口 $port UDP" "SUCCESS" "正在监听"
    else
      add_check_result "端口 $port UDP" "WARNING" "未在监听"
    fi
  else
    add_check_result "端口 $port UDP" "WARNING" "无法检查（缺少 ss 或 netstat 工具）"
  fi
done

# 检查 Web 管理端口（HTTP）
if command -v ss >/dev/null 2>&1; then
  if ss -tlnp | grep -q ":51821 "; then
    add_check_result "Web 管理端口 51821" "SUCCESS" "正在监听"
  else
    add_check_result "Web 管理端口 51821" "WARNING" "未在监听"
  fi
elif command -v netstat >/dev/null 2>&1; then
  if netstat -tlnp 2>/dev/null | grep -q ":51821 "; then
    add_check_result "Web 管理端口 51821" "SUCCESS" "正在监听"
  else
    add_check_result "Web 管理端口 51821" "WARNING" "未在监听"
  fi
else
  add_check_result "Web 管理端口 51821" "WARNING" "无法检查（缺少 ss 或 netstat 工具）"
fi

# 3. 系统资源检查
log_message "$LOG_FILE" "开始系统资源检查..."

# CPU 使用率检查
cpu_usage=$(top -bn1 | grep "^%Cpu" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null)
if [ -n "$cpu_usage" ]; then
  cpu_usage_int=${cpu_usage%.*}  # 去掉小数部分
  if [ "$cpu_usage_int" -lt 80 ]; then
    add_check_result "CPU 使用率" "SUCCESS" "${cpu_usage}%"
  elif [ "$cpu_usage_int" -lt 90 ]; then
    add_check_result "CPU 使用率" "WARNING" "${cpu_usage}%"
  else
    add_check_result "CPU 使用率" "ERROR" "${cpu_usage}% (过高)"
  fi
else
  add_check_result "CPU 使用率" "WARNING" "无法获取"
fi

# 内存使用率检查
memory_info=$(free | grep "^Mem:")
if [ -n "$memory_info" ]; then
  total_mem=$(echo "$memory_info" | awk '{print $2}')
  used_mem=$(echo "$memory_info" | awk '{print $3}')
  memory_usage=$((used_mem * 100 / total_mem))
  
  if [ "$memory_usage" -lt 80 ]; then
    add_check_result "内存使用率" "SUCCESS" "${memory_usage}%"
  elif [ "$memory_usage" -lt 90 ]; then
    add_check_result "内存使用率" "WARNING" "${memory_usage}%"
  else
    add_check_result "内存使用率" "ERROR" "${memory_usage}% (过高)"
  fi
else
  add_check_result "内存使用率" "WARNING" "无法获取"
fi

# 磁盘使用率检查
disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ -n "$disk_usage" ]; then
  if [ "$disk_usage" -lt 80 ]; then
    add_check_result "根分区使用率" "SUCCESS" "${disk_usage}%"
  elif [ "$disk_usage" -lt 90 ]; then
    add_check_result "根分区使用率" "WARNING" "${disk_usage}%"
  else
    add_check_result "根分区使用率" "ERROR" "${disk_usage}% (过高)"
  fi
else
  add_check_result "根分区使用率" "WARNING" "无法获取"
fi

# 4. 安全检查
log_message "$LOG_FILE" "开始安全检查..."

# SSH 服务检查
if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
  add_check_result "SSH 服务" "SUCCESS" "运行正常"
else
  add_check_result "SSH 服务" "ERROR" "未运行"
fi

# fail2ban 检查
if command -v fail2ban-client >/dev/null 2>&1; then
  if systemctl is-active fail2ban >/dev/null 2>&1; then
    banned_ips=$(fail2ban-client status 2>/dev/null | grep -o "Number of jail:.*" || echo "无法获取状态")
    add_check_result "fail2ban 服务" "SUCCESS" "运行正常 ($banned_ips)"
  else
    add_check_result "fail2ban 服务" "WARNING" "未运行"
  fi
else
  add_check_result "fail2ban 工具" "WARNING" "未安装"
fi

# 5. 连接统计
log_message "$LOG_FILE" "开始连接统计..."

# 统计在线客户端
if command -v wg >/dev/null 2>&1; then
  total_peers=0
  active_peers=0
  
  for interface in $(wg show interfaces 2>/dev/null); do
    interface_peers=$(wg show "$interface" peers 2>/dev/null | wc -l)
    total_peers=$((total_peers + interface_peers))
    
    # 检查最近有流量的客户端（最近5分钟）
    current_time=$(date +%s)
    for peer in $(wg show "$interface" peers 2>/dev/null); do
      latest_handshake=$(wg show "$interface" latest-handshakes 2>/dev/null | grep "$peer" | awk '{print $2}')
      if [ -n "$latest_handshake" ] && [ "$latest_handshake" -gt 0 ]; then
        time_diff=$((current_time - latest_handshake))
        if [ "$time_diff" -lt 300 ]; then  # 5分钟内
          active_peers=$((active_peers + 1))
        fi
      fi
    done
  done
  
  add_check_result "客户端统计" "SUCCESS" "总计 $total_peers 个，活跃 $active_peers 个"
else
  add_check_result "客户端统计" "WARNING" "无法统计（wg 命令不可用）"
fi

# 6. 生成检查摘要
log_message "$LOG_FILE" "健康检查完成"
log_message "$LOG_FILE" "检查项目总数: $CHECK_COUNT"
log_message "$LOG_FILE" "成功: $SUCCESS_COUNT"
log_message "$LOG_FILE" "警告: $WARNING_COUNT" 
log_message "$LOG_FILE" "错误: $ERROR_COUNT"

# 根据检查结果确定整体状态
if [ "$ERROR_COUNT" -gt 0 ]; then
  overall_status="异常"
  status_emoji="❌"
elif [ "$WARNING_COUNT" -gt 0 ]; then
  overall_status="警告"
  status_emoji="⚠️"
else
  overall_status="良好"
  status_emoji="✅"
fi

# 准备通知内容
notification_summary="检查项目: $CHECK_COUNT 个\n成功: $SUCCESS_COUNT | 警告: $WARNING_COUNT | 错误: $ERROR_COUNT"

# 如果有问题，包含详细信息；否则只显示摘要
if [ "$ERROR_COUNT" -gt 0 ] || [ "$WARNING_COUNT" -gt 3 ]; then
  # 有严重问题或警告过多，发送详细信息
  notification_details="$notification_summary\n\n检查详情:\n$HEALTH_DETAILS"
  
  if [ "$ERROR_COUNT" -gt 0 ]; then
    task_failure "WireGuard 健康检查" "$LOG_FILE" "发现 $ERROR_COUNT 个错误，$WARNING_COUNT 个警告" 1
  else
    task_success "WireGuard 健康检查" "$LOG_FILE" "$status_emoji 系统状态：$overall_status\n$notification_details"
  fi
elif [ "$WARNING_COUNT" -gt 0 ]; then
  # 只有少量警告，发送摘要
  task_success "WireGuard 健康检查" "$LOG_FILE" "$status_emoji 系统状态：$overall_status\n$notification_summary\n\n有 $WARNING_COUNT 个项目需要关注，详情请查看日志"
else
  # 一切正常，发送简要通知
  task_success "WireGuard 健康检查" "$LOG_FILE" "$status_emoji 系统状态：$overall_status\n$notification_summary"
fi

echo "" >> "$LOG_FILE"
exit 0