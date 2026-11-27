#!/bin/bash

#
# 边缘节点 (rrpi / Peer) 防火墙基线
#
# 作用: 默认拒绝入站, 仅放行 SSH、本地局域网与 WireGuard 隧道的业务白名单。
#
# 注意:
# - 脚本会先执行 ufw --force reset 清空现有规则, 再按本文件的列表重建。
# - 新增业务端口时只改下方 WG_PORTS 数组, 不要手工执行 ufw allow。
# - Docker 容器会绕过 UFW 规则, 需要配合 server-forge 项目的 docker-ufw-guard.sh 兜底。
#
# 用法: sudo ./firewall-rrpi.sh
#

set -o pipefail

# --- 管理通道与本地局域网 ---
SSH_PORT=33489
LAN_IFACE="eth0"
LAN_CIDR="192.168.31.0/24"

# --- 仅向网关 (wg0) 开放的业务端口, 格式: 端口:服务名 ---
WG_PORTS=(
  "5778:n8n"
  "8088:FDM"
  "7080:TimeTagger"
  "7113:PSWD"
  "6781:PDF-Viewer"
  "9888:Blank"
  "9323:Qipao API"
  "9123:Qipao MongoDB"
  "9697:Qipao Redis"
)

#
# 主函数
#
main() {
  if [ "$EUID" -ne 0 ]; then
    echo "[错误] 此脚本需要以 root 权限运行。请使用: sudo $0"
    exit 1
  fi

  echo "[信息] 重置 UFW 并设置默认策略..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  echo "[信息] 放行管理通道与本地局域网..."
  ufw allow "${SSH_PORT}/tcp" comment 'SSH Remote Management'
  ufw allow in on "$LAN_IFACE" from "$LAN_CIDR" comment 'Local Physical LAN'

  echo "[信息] 放行 WireGuard 隧道的业务白名单..."
  local entry port name
  for entry in "${WG_PORTS[@]}"; do
    port="${entry%%:*}"
    name="${entry#*:}"
    ufw allow in on wg0 to any port "$port" proto tcp comment "${name} for rwpn"
    echo "    - ${port}/tcp (${name})"
  done

  echo "[信息] 激活防火墙..."
  ufw --force enable
  ufw status verbose
}

# 执行主函数
main
