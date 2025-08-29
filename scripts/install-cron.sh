#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "错误：此脚本需要 root 权限运行"
  echo "请使用：sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNS_SCRIPT="$SCRIPT_DIR/dns-refresh.sh"
REBOOT_SCRIPT="$SCRIPT_DIR/server-reboot.sh"
HEALTHCHECK_SCRIPT="$SCRIPT_DIR/wireguard-healthcheck.sh"

# 检查必要脚本是否存在
if [ ! -f "$DNS_SCRIPT" ]; then
  echo "错误：DNS 刷新脚本 $DNS_SCRIPT 不存在"
  exit 1
fi

if [ ! -f "$REBOOT_SCRIPT" ]; then
  echo "错误：服务器重启脚本 $REBOOT_SCRIPT 不存在"
  exit 1
fi

if [ ! -f "$HEALTHCHECK_SCRIPT" ]; then
  echo "错误：WireGuard 健康检查脚本 $HEALTHCHECK_SCRIPT 不存在"
  exit 1
fi

if [ ! -x "$DNS_SCRIPT" ]; then
  echo "设置 DNS 刷新脚本的可执行权限..."
  chmod +x "$DNS_SCRIPT" || {
    echo "错误：无法设置 $DNS_SCRIPT 的可执行权限"
    exit 1
  }
fi

if [ ! -x "$REBOOT_SCRIPT" ]; then
  echo "设置服务器重启脚本的可执行权限..."
  chmod +x "$REBOOT_SCRIPT" || {
    echo "错误：无法设置 $REBOOT_SCRIPT 的可执行权限"
    exit 1
  }
fi

if [ ! -x "$HEALTHCHECK_SCRIPT" ]; then
  echo "设置 WireGuard 健康检查脚本的可执行权限..."
  chmod +x "$HEALTHCHECK_SCRIPT" || {
    echo "错误：无法设置 $HEALTHCHECK_SCRIPT 的可执行权限"
    exit 1
  }
fi

# 验证脚本是否能够正常运行（进行语法检查）
echo "验证脚本语法..."
bash -n "$DNS_SCRIPT" || {
  echo "错误：DNS 刷新脚本语法错误"
  exit 1
}
bash -n "$REBOOT_SCRIPT" || {
  echo "错误：服务器重启脚本语法错误"
  exit 1
}
bash -n "$HEALTHCHECK_SCRIPT" || {
  echo "错误：WireGuard 健康检查脚本语法错误"
  exit 1
}

echo "添加定时任务："
echo "  - 每天上海时间早上 6:00 执行 DNS 刷新"
echo "  - 每天上海时间早上 6:05 执行服务器重启"
echo "  - 每小时的第 1 分钟执行 WireGuard 健康检查"

# 备份现有的 crontab
CRONTAB_BACKUP="/tmp/crontab_backup_$(date +%Y%m%d_%H%M%S)"
crontab -l > "$CRONTAB_BACKUP" 2>/dev/null || touch "$CRONTAB_BACKUP"
echo "已备份现有 crontab 到 $CRONTAB_BACKUP"

# 添加新的定时任务
(crontab -l 2>/dev/null | grep -v "$DNS_SCRIPT" | grep -v "$REBOOT_SCRIPT" | grep -v "$HEALTHCHECK_SCRIPT"; echo "0 6 * * * TZ='Asia/Shanghai' $DNS_SCRIPT"; echo "5 6 * * * TZ='Asia/Shanghai' $REBOOT_SCRIPT"; echo "1 * * * * TZ='Asia/Shanghai' $HEALTHCHECK_SCRIPT") | crontab - || {
  echo "错误：无法更新 crontab，正在恢复备份..."
  crontab "$CRONTAB_BACKUP" 2>/dev/null
  exit 1
}

# 验证 crontab 是否正确添加
if crontab -l | grep -q "$DNS_SCRIPT" && crontab -l | grep -q "$REBOOT_SCRIPT" && crontab -l | grep -q "$HEALTHCHECK_SCRIPT"; then
  echo "定时任务添加成功！"
  echo "当前 crontab 配置："
  crontab -l | grep -E "($DNS_SCRIPT|$REBOOT_SCRIPT|$HEALTHCHECK_SCRIPT)" || {
    echo "警告：无法显示 crontab 配置"
  }

  echo ""
  echo "设置时区为上海..."
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || {
      echo "警告：无法设置系统时区，请手动执行：timedatectl set-timezone Asia/Shanghai"
    }
    # 验证时区设置
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null)
    if [ "$current_tz" = "Asia/Shanghai" ]; then
      echo "时区设置成功：$current_tz"
    else
      echo "警告：时区设置可能失败，当前时区：$current_tz"
    fi
  else
    echo "警告：timedatectl 命令不可用，请手动设置时区"
  fi

  echo ""
  echo "启动并启用 cron 服务..."

  # 尝试启动 cron 服务（不同系统可能有不同的服务名）
  CRON_ENABLED=false
  for service_name in cron crond; do
    if systemctl enable "$service_name" 2>/dev/null; then
      echo "$service_name 服务已启用"
      CRON_ENABLED=true
      break
    fi
  done

  if [ "$CRON_ENABLED" = false ]; then
    echo "警告：无法启用 cron 服务，请手动检查"
  fi

  # 尝试启动 cron 服务
  CRON_STARTED=false
  for service_name in cron crond; do
    if systemctl start "$service_name" 2>/dev/null; then
      echo "$service_name 服务已启动"
      CRON_STARTED=true
      break
    fi
  done

  if [ "$CRON_STARTED" = false ]; then
    echo "警告：无法启动 cron 服务，请手动检查"
  else
    # 验证 cron 服务状态
    sleep 1
    if systemctl is-active cron >/dev/null 2>&1 || systemctl is-active crond >/dev/null 2>&1; then
      echo "cron 服务运行正常"
    else
      echo "警告：cron 服务可能未正常运行"
    fi
  fi

  echo ""
  echo "安装完成！"
  echo "定时任务说明："
  echo "  - DNS 将在每天上海时间早上 6:00 自动刷新"
  echo "  - 服务器将在每天上海时间早上 6:05 自动重启"
  echo "  - WireGuard 健康检查每小时第 1 分钟执行"
  echo ""
  echo "日志文件位置（采用轮转机制）："
  echo "  - DNS 刷新日志：/var/log/dns-refresh-*.log"
  echo "  - 服务器重启日志：/var/log/server-reboot-*.log"
  echo "  - WireGuard 健康检查日志：/var/log/wireguard-healthcheck-*.log"
  echo ""
  echo "推送通知："
  echo "  - 所有任务的成功/失败状态将推送到手机"
  echo "  - 确保已配置 .env 文件中的 SENDKEY"

  # 清理备份文件
  rm -f "$CRONTAB_BACKUP" 2>/dev/null

else
  echo "错误：定时任务添加失败"
  echo "正在恢复原有 crontab 配置..."
  crontab "$CRONTAB_BACKUP" 2>/dev/null || {
    echo "警告：无法恢复原有 crontab 配置"
  }
  exit 1
fi
