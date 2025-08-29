#!/bin/bash

# 方糖酱推送通知工具函数
# 用于发送任务执行结果到手机

# 方糖酱发送消息函数
# 参数1: 消息标题
# 参数2: 消息内容
# 参数3: 发送密钥 (可选，如果不提供则从配置文件读取)
sc_send() {
  local text="$1"
  local desp="$2"
  local key="${3:-}"

  if [ -z "$text" ]; then
    echo "错误：消息标题不能为空"
    return 1
  fi

  # 如果没有提供密钥，尝试从配置文件读取
  if [ -z "$key" ]; then
    local config_file
    config_file="$(dirname "${BASH_SOURCE[0]}")/../.env"
    if [ -f "$config_file" ]; then
      # 读取配置文件中的 SENDKEY
      key=$(grep '^SENDKEY=' "$config_file" | cut -d'=' -f2 | tr -d '"'"'"'')
    fi

    if [ -z "$key" ]; then
      echo "错误：未找到发送密钥，请在配置文件中设置 SENDKEY"
      return 1
    fi
  fi

  # URL 编码函数
  url_encode() {
    local string="$1"
    echo -n "$string" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g'
  }

  # 对消息内容进行 URL 编码
  local encoded_text
  encoded_text=$(url_encode "$text")
  local encoded_desp
  encoded_desp=$(url_encode "$desp")

  local postdata="text=${encoded_text}&desp=${encoded_desp}"
  local opts=(
    "--header" "Content-type: application/x-www-form-urlencoded"
    "--data" "$postdata"
    "--connect-timeout" "30"
    "--max-time" "60"
    "--retry" "3"
    "--retry-delay" "5"
  )

  # 判断 key 是否以 "sctp" 开头，选择不同的 URL
  local url
  if [[ "$key" =~ ^sctp([0-9]+)t ]]; then
    # 使用正则表达式提取数字部分
    local num=${BASH_REMATCH[1]}
    url="https://${num}.push.ft07.com/send/${key}.send"
  else
    url="https://sctapi.ftqq.com/${key}.send"
  fi

  # 使用动态生成的 url 发送请求
  local result
  result=$(curl -X POST -s -o /dev/null -w "%{http_code}" "$url" "${opts[@]}" 2>/dev/null)

  if [ "$result" = "200" ]; then
    echo "推送成功"
    return 0
  else
    echo "推送失败，HTTP 状态码: $result"
    return 1
  fi
}

# 发送任务成功通知
# 参数1: 任务名称
# 参数2: 任务详细信息 (可选)
send_success_notification() {
  local task_name="$1"
  local task_details="${2:-}"

  if [ -z "$task_name" ]; then
    echo "错误：任务名称不能为空"
    return 1
  fi

  local title="✅ ${task_name} 任务执行成功"
  local content
  content="任务：${task_name}\n执行时间：$(date '+%Y-%m-%d %H:%M:%S')\n状态：成功"

  if [ -n "$task_details" ]; then
    content="${content}\n\n详细信息：\n${task_details}"
  fi

  sc_send "$title" "$content"
}

# 发送任务失败通知
# 参数1: 任务名称
# 参数2: 错误信息
# 参数3: 任务详细信息 (可选)
send_failure_notification() {
  local task_name="$1"
  local error_message="$2"
  local task_details="${3:-}"

  if [ -z "$task_name" ]; then
    echo "错误：任务名称不能为空"
    return 1
  fi

  if [ -z "$error_message" ]; then
    error_message="未知错误"
  fi

  local title="❌ ${task_name} 任务执行失败"
  local content
  content="任务：${task_name}\n执行时间：$(date '+%Y-%m-%d %H:%M:%S')\n状态：失败\n错误：${error_message}"

  if [ -n "$task_details" ]; then
    content="${content}\n\n详细信息：\n${task_details}"
  fi

  sc_send "$title" "$content"
}

# 发送服务器状态通知
# 参数1: 状态类型 (startup|shutdown|restart)
# 参数2: 额外信息 (可选)
send_server_status_notification() {
  local status_type="$1"
  local extra_info="${2:-}"

  local title
  local content

  case "$status_type" in
    "startup")
      title="🚀 服务器启动通知"
      content="服务器已启动\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
      ;;
    "shutdown")
      title="🔌 服务器关机通知"
      content="服务器即将关机\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
      ;;
    "restart")
      title="🔄 服务器重启通知"
      content="服务器即将重启\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
      ;;
    *)
      echo "错误：不支持的状态类型: $status_type"
      return 1
      ;;
  esac

  if [ -n "$extra_info" ]; then
    content="${content}\n\n${extra_info}"
  fi

  sc_send "$title" "$content"
}

# 检查方糖酱配置是否有效
check_notification_config() {
  local config_file
  config_file="$(dirname "${BASH_SOURCE[0]}")/../.env"

  if [ ! -f "$config_file" ]; then
    echo "警告：配置文件 $config_file 不存在"
    return 1
  fi

  local sendkey
  sendkey=$(grep '^SENDKEY=' "$config_file" | cut -d'=' -f2 | tr -d '"'"'"'')

  if [ -z "$sendkey" ]; then
    echo "警告：配置文件中未设置 SENDKEY"
    return 1
  fi

  # 验证密钥格式
  if [[ ! "$sendkey" =~ ^(SCT|sctp)[0-9a-zA-Z]+ ]]; then
    echo "警告：SENDKEY 格式可能不正确"
    return 1
  fi

  echo "方糖酱配置检查通过"
  return 0
}

# 如果脚本被直接执行（而非被source），提供使用示例
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "方糖酱推送通知工具函数库"
  echo ""
  echo "使用方式："
  echo "source $0"
  echo ""
  echo "主要函数："
  echo "1. sc_send <标题> <内容> [密钥]"
  echo "   - 发送自定义消息"
  echo ""
  echo "2. send_success_notification <任务名称> [详细信息]"
  echo "   - 发送任务成功通知"
  echo ""
  echo "3. send_failure_notification <任务名称> <错误信息> [详细信息]"
  echo "   - 发送任务失败通知"
  echo ""
  echo "4. send_server_status_notification <状态类型> [额外信息]"
  echo "   - 发送服务器状态通知 (startup|shutdown|restart)"
  echo ""
  echo "5. check_notification_config"
  echo "   - 检查方糖酱配置是否有效"
  echo ""
  echo "配置文件："
  echo "在项目根目录创建 .env 文件，内容如下："
  echo 'SENDKEY="your_sendkey_here"'
fi
