# 任务: 将本机接入现有 WireGuard 网络

> 用法: 把本文件全文复制给 AI 执行体, 将 `<配置文件内容>` 替换为 wg-easy 生成的客户端配置。每个检查点必须通过, 失败即停。

你在一台 Ubuntu 服务器上执行装配。目标是让本机接入 10.8.0.0/24 虚拟内网, 并通过全部检查点。失败时停止并报告, 不要自行重启网络或服务器。

## 输入

客户端配置 (完整内容):

```ini
<配置文件内容>
```

已知网络信息:
- 网关 rwpn: 10.8.0.1, 公网 Endpoint 139.196.99.84:31820/udp
- 树莓派 rrpi: 10.8.0.3

## 执行步骤

### 1. 环境预检

```bash
. /etc/os-release && echo "$PRETTY_NAME"
uname -r
ip link show | head
```

确认: Ubuntu 系统, 内核 >= 5.6 (内置 WireGuard), 有 root 或 sudo 权限。

**检测既有透明代理 (xray)**, 这台机器可能已经按 `~/xray` 方案装了系统级透明代理。装配 WireGuard 前后都必须保证它不受影响:

```bash
XRAY_ACTIVE=0
XRAY_NAT=0

systemctl is-active --quiet xray && XRAY_ACTIVE=1
iptables -t nat -L XRAY_NAT -n >/dev/null 2>&1 && XRAY_NAT=1

echo "xray.service active: $XRAY_ACTIVE"
echo "XRAY_NAT chain exists: $XRAY_NAT"

if [ "$XRAY_ACTIVE" = "1" ] || [ "$XRAY_NAT" = "1" ]; then
    echo "检测到既有透明代理, 后续 UFW 收尾必须走兼容分支"
    systemctl status xray --no-pager 2>/dev/null | head -5
    iptables -t nat -L XRAY_NAT -n 2>/dev/null | head -12
fi
```

如果两个变量任意一个为 1, 记下当前状态, 第 6 步的安全收尾与第 7 步的检查点都要按「xray 共存」处理。如果都是 0, 说明是干净机器, 按常规流程走。

### 2. 安装

```bash
apt update && apt install -y wireguard
```

### 3. 写入配置

```bash
install -m 600 /dev/stdin /etc/wireguard/wg0.conf <<'WGEOF'
<配置文件内容>
WGEOF
```

写入后校验:

```bash
grep -E '^(Address|Endpoint|AllowedIPs)' /etc/wireguard/wg0.conf
```

确认 `AllowedIPs = 10.8.0.0/24`。如果包含 `0.0.0.0/0` 立即停止并报告配置错误。

### 4. 启动

```bash
systemctl enable --now wg-quick@wg0
sleep 3
wg show
```

## 检查点 (全部通过才算成功)

| # | 检查项 | 命令 | 通过标准 |
|---|---|---|---|
| 1 | 接口已创建 | `ip link show wg0` | 存在且状态 UP |
| 2 | 地址已分配 | `ip -4 addr show wg0` | 有 10.8.0.x/24 |
| 3 | 握手成功 | `wg show wg0 latest-handshakes` | 时间戳非 0 |
| 4 | 网关可达 | `ping -c 3 10.8.0.1` | 3 个包全通 |
| 5 | 树莓派可达 | `ping -c 3 10.8.0.3` | 3 个包全通 |
| 6 | 路由正确 | `ip route show 10.8.0.0/24` | 输出包含 wg0 |
| 7 | 开机自启 | `systemctl is-enabled wg-quick@wg0` | enabled |
| 8 | xray 服务未受影响 | `systemctl is-active xray` | 装配前为 active 时仍为 active |
| 9 | 透明代理规则仍在 | `iptables -t nat -L XRAY_NAT -n` | 装配前存在时仍存在 |
| 10 | 透明代理仍可用 | `curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://www.google.com` | 200 或 301/302 (能出去即算通) |

第 8 到 10 项只在第 1 步检测到 xray 时才执行; 干净机器跳过, 在报告中注明「无既有透明代理」。

## 失败处理

任何检查点失败时, 输出:

1. 失败的是第几项
2. 相关命令的完整输出
3. 初步判断 (接口未起 / 无握手 / 握手成功但 ping 不通)
4. 建议的下一步, 不要自行修改配置或重启

常见分支:

- 无握手: 出站 UDP 到 139.196.99.84:31820 被防火墙拦, 或 Endpoint 配置错误
- 有握手但 ping 10.8.0.1 不通: 服务端 AllowedIPs 未包含本机 IP
- ping 10.8.0.1 通但 10.8.0.3 不通: rrpi 的 UFW 未放行, 或 rrpi 未在线

## 安全收尾 (与本任务同批执行)

### 干净机器 (第 1 步检测到 xray 不存在)

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable
ufw status verbose
```

### xray 共存机器 (第 1 步检测到 xray 存在)

`ufw --force enable` 会 reload 整个 filter 表, 虽然不直接碰 nat 表的 `XRAY_NAT`, 但会触发 Docker 重新应用转发规则。按下面顺序执行, 每步都要验证:

```bash
# 1. 记录装配前的 xray 状态
systemctl is-active xray
iptables -t nat -S XRAY_NAT > /root/xray-nat-before.txt

# 2. 只加必要规则, 不做 ufw default 重置
ufw allow 22/tcp comment 'SSH'
for br in $(ls /sys/class/net | grep -E '^(docker|br-)'); do
    ufw allow in on "$br" comment "Docker bridge $br"
done
ufw --force enable
ufw status verbose

# 3. 立即复查 xray 是否还活着
systemctl is-active xray
iptables -t nat -L XRAY_NAT -n | head -15

# 4. 如果 xray 服务挂了, 重新拉起
#    systemctl restart xray

# 5. 如果 XRAY_NAT 链丢了, 重新加载规则单元
#    systemctl restart xray-nat
```

如果第 3 步发现 xray 已停或链已丢失, 先执行第 4、5 步恢复, 再继续验证透明代理是否可用。恢复不了就停止装配并报告, 不要继续改防火墙。

### 通用收尾

如果本机要为内网提供其他服务, 逐条 `ufw allow in on wg0 to any port <端口>`, 不要用 `ufw allow <端口>` 放到公网。

## 输出格式

```text
装配结果: 成功 / 失败
检查点: 7/7 通过 (无 xray) 或 10/10 通过 (xray 共存)
接口地址: 10.8.0.x
握手时间: <相对时间>
网关延迟: <ms>
树莓派延迟: <ms>
xray 状态: 未检测到 / active / 已恢复
透明代理: 未检测到 / XRAY_NAT 存在且可用
防火墙: ufw active, 默认拒绝入站
备注: <任何异常>
```
