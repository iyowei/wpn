#!/bin/bash

# 引入日志轮转工具函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log-rotation.sh" || {
    echo "错误：无法加载日志轮转工具函数"
    exit 1
}

# 创建轮转日志文件
LOG_FILE=$(create_rotation_log "server-reboot") || {
    echo "错误：无法创建日志文件"
    exit 1
}

# 清理超过7天的旧日志文件
cleanup_old_logs "server-reboot" 7

if [ "$EUID" -ne 0 ]; then
    echo "错误：此脚本需要 root 权限运行"
    echo "请使用：sudo $0"
    task_failure "服务器重启" "$LOG_FILE" "权限不足，需要 root 权限"
    exit 1
fi

# 开始任务
task_start "服务器重启" "$LOG_FILE"

uptime_info=$(uptime 2>/dev/null || echo "无法获取系统运行时间")
log_message "$LOG_FILE" "当前系统运行时间：$uptime_info"

memory_info=$(free -h 2>/dev/null | grep "Mem:" || echo "无法获取内存信息")
log_message "$LOG_FILE" "当前内存使用情况：$memory_info"

disk_info=$(df -h / 2>/dev/null | tail -1 || echo "无法获取磁盘信息")
log_message "$LOG_FILE" "根分区磁盘使用情况：$disk_info"

if command -v docker >/dev/null 2>&1; then
    running_containers=$(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null)
    if [ -n "$running_containers" ]; then
        log_message "$LOG_FILE" "当前运行的 Docker 容器："
        echo "$running_containers" >> "$LOG_FILE"
    else
        log_message "$LOG_FILE" "没有运行中的 Docker 容器"
    fi
else
    log_message "$LOG_FILE" "Docker 未安装或不可用"
fi

log_message "$LOG_FILE" "同步文件系统缓存到磁盘..."
sync 2>/dev/null || {
    log_message "$LOG_FILE" "警告：sync 命令执行失败"
}

# 发送重启通知
if [ "$NOTIFICATION_ENABLED" = "true" ]; then
    # 收集系统信息作为通知内容
    system_info="系统运行时间：$uptime_info"
    if [ -n "$memory_info" ]; then
        system_info="$system_info\n内存使用：$memory_info"
    fi
    if [ -n "$disk_info" ]; then
        system_info="$system_info\n磁盘使用：$disk_info"
    fi
    
    send_server_status_notification "restart" "$system_info" 2>/dev/null || {
        log_message "$LOG_FILE" "发送重启通知失败"
    }
fi

log_message "$LOG_FILE" "立即重启服务器..."
echo "" >> "$LOG_FILE"

# 尝试多种重启方式，确保能够成功重启
REBOOT_SUCCESS=false

if command -v shutdown >/dev/null 2>&1; then
    if shutdown -r now "系统正在自动重启..." 2>/dev/null; then
        REBOOT_SUCCESS=true
    else
        log_message "$LOG_FILE" "shutdown 命令失败，尝试 reboot"
        if reboot 2>/dev/null; then
            REBOOT_SUCCESS=true
        else
            log_message "$LOG_FILE" "reboot 命令也失败，尝试 systemctl"
            if systemctl reboot 2>/dev/null; then
                REBOOT_SUCCESS=true
            else
                log_message "$LOG_FILE" "所有重启命令都失败"
                task_failure "服务器重启" "$LOG_FILE" "所有重启命令都失败，无法重启系统" 1
                exit 1
            fi
        fi
    fi
else
    if reboot 2>/dev/null; then
        REBOOT_SUCCESS=true
    else
        if systemctl reboot 2>/dev/null; then
            REBOOT_SUCCESS=true
        else
            log_message "$LOG_FILE" "无法重启系统"
            task_failure "服务器重启" "$LOG_FILE" "无法重启系统，所有重启方法都失败" 1
            exit 1
        fi
    fi
fi

# 如果到这里说明重启命令已成功执行
if [ "$REBOOT_SUCCESS" = "true" ]; then
    task_success "服务器重启" "$LOG_FILE" "重启命令已成功执行，系统即将重启"
fi