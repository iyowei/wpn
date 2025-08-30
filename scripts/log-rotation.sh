#!/bin/bash

# 日志轮转工具函数
# 为脚本任务创建带有任务名称和精确执行时间的日志文件

# 引入推送通知工具函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/notification.sh" ]; then
    source "$SCRIPT_DIR/notification.sh"
    NOTIFICATION_ENABLED=true
else
    NOTIFICATION_ENABLED=false
    echo "警告：推送通知功能不可用，notification.sh 文件不存在"
fi

# 创建轮转日志文件函数
# 参数1: 任务名称 (例如: "dns-refresh", "server-reboot")
# 参数2: 日志目录 (可选，默认为 /var/log)
create_rotation_log() {
    local task_name="$1"
    local log_dir="${2:-/var/log}"

    if [ -z "$task_name" ]; then
        echo "错误：未提供任务名称"
        return 1
    fi

    # 获取精确的执行时间 (年月日-时分秒)
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')

    # 构建新的日志文件路径
    local new_log_file="$log_dir/${task_name}-${timestamp}.log"

    # 确保日志目录存在
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" || {
            echo "错误：无法创建日志目录 $log_dir"
            return 1
        }
    fi

    # 创建新日志文件
    touch "$new_log_file" || {
        echo "错误：无法创建日志文件 $new_log_file"
        return 1
    }

    # 输出新日志文件路径，供调用脚本使用
    echo "$new_log_file"
    return 0
}

# 清理旧日志文件函数
# 参数1: 任务名称
# 参数2: 保留天数 (默认30天)
# 参数3: 日志目录 (可选，默认为 /var/log)
cleanup_old_logs() {
    local task_name="$1"
    local keep_days="${2:-30}"
    local log_dir="${3:-/var/log}"

    if [ -z "$task_name" ]; then
        echo "错误：未提供任务名称"
        return 1
    fi

    # 查找并删除超过指定天数的日志文件
    if [ -d "$log_dir" ]; then
        find "$log_dir" -name "${task_name}-*.log" -type f -mtime +"${keep_days}" -delete 2>/dev/null

        # 记录清理操作
        local cleanup_count
        cleanup_count=$(find "$log_dir" -name "${task_name}-*.log" -type f -mtime +"${keep_days}" 2>/dev/null | wc -l)
        if [ "$cleanup_count" -gt 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 已清理 $cleanup_count 个超过 ${keep_days} 天的 ${task_name} 日志文件"
        fi
    fi

    return 0
}

# 记录日志函数
# 参数1: 日志文件路径
# 参数2: 日志内容
log_message() {
    local log_file="$1"
    local message="$2"

    if [ -z "$log_file" ] || [ -z "$message" ]; then
        echo "错误：缺少日志文件路径或日志内容"
        return 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}

# 任务开始记录函数
# 参数1: 任务名称
# 参数2: 日志文件路径
task_start() {
    local task_name="$1"
    local log_file="$2"

    if [ -z "$task_name" ] || [ -z "$log_file" ]; then
        echo "错误：缺少任务名称或日志文件路径"
        return 1
    fi

    log_message "$log_file" "开始执行 $task_name 任务"

    # 记录任务开始时间到全局变量（用于计算执行时长）
    export TASK_START_TIME
    TASK_START_TIME=$(date +%s)
    export CURRENT_TASK_NAME="$task_name"
    export CURRENT_LOG_FILE="$log_file"

    return 0
}

# 任务成功完成函数
# 参数1: 任务名称
# 参数2: 日志文件路径
# 参数3: 成功信息 (可选)
task_success() {
    local task_name="$1"
    local log_file="$2"
    local success_message="${3:-任务执行成功}"

    if [ -z "$task_name" ] || [ -z "$log_file" ]; then
        echo "错误：缺少任务名称或日志文件路径"
        return 1
    fi

    # 计算执行时长
    local duration=""
    if [ -n "$TASK_START_TIME" ]; then
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - TASK_START_TIME))
        duration="执行时长：${elapsed} 秒"
    fi

    log_message "$log_file" "$success_message"
    log_message "$log_file" "任务执行完成"

    if [ -n "$duration" ]; then
        log_message "$log_file" "$duration"
    fi

    # 发送成功通知
    if [ "$NOTIFICATION_ENABLED" = "true" ]; then
        local details="$success_message"
        if [ -n "$duration" ]; then
            details="$details

$duration"
        fi

        send_success_notification "$task_name" "$details" 2>/dev/null || {
            log_message "$log_file" "推送成功通知失败"
        }
    fi

    return 0
}

# 任务失败函数
# 参数1: 任务名称
# 参数2: 日志文件路径
# 参数3: 错误信息
# 参数4: 退出码 (可选，默认为1)
task_failure() {
    local task_name="$1"
    local log_file="$2"
    local error_message="$3"
    local exit_code="${4:-1}"

    if [ -z "$task_name" ] || [ -z "$log_file" ] || [ -z "$error_message" ]; then
        echo "错误：缺少必要参数"
        return 1
    fi

    # 计算执行时长
    local duration=""
    if [ -n "$TASK_START_TIME" ]; then
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - TASK_START_TIME))
        duration="执行时长：${elapsed} 秒"
    fi

    log_message "$log_file" "任务执行失败：$error_message"

    if [ -n "$duration" ]; then
        log_message "$log_file" "$duration"
    fi

    # 发送失败通知
    if [ "$NOTIFICATION_ENABLED" = "true" ]; then
        local details="$error_message"
        if [ -n "$duration" ]; then
            details="$details

$duration"
        fi

        send_failure_notification "$task_name" "$error_message" "$details" 2>/dev/null || {
            log_message "$log_file" "推送失败通知失败"
        }
    fi

    return "$exit_code"
}

# 如果脚本被直接执行（而非被source），提供使用示例
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "日志轮转工具函数库"
  echo ""
  echo "使用方式："
  echo "source $0"
  echo ""
  echo "主要函数："
  echo "1. create_rotation_log <任务名称> [日志目录]"
  echo "   - 创建带时间戳的新日志文件"
  echo "   - 返回新日志文件的完整路径"
  echo ""
  echo "2. cleanup_old_logs <任务名称> [保留天数] [日志目录]"
  echo "   - 清理超过指定天数的旧日志文件"
  echo "   - 默认保留30天"
  echo ""
  echo "3. log_message <日志文件路径> <日志内容>"
  echo "   - 向指定日志文件写入带时间戳的消息"
  echo ""
  echo "示例："
  echo "# 创建DNS刷新任务的轮转日志"
  echo "LOG_FILE=\$(create_rotation_log \"dns-refresh\")"
  echo "log_message \"\$LOG_FILE\" \"开始执行DNS刷新任务\""
  echo "cleanup_old_logs \"dns-refresh\" 7  # 保留7天"
fi
