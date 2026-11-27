# 端节点

> 本文只讲端节点的 WireGuard 接入。主机层装配、硬件核验与性能调优见 server-forge 的 `docs/host-bootstrap.md` 与 `docs/host-tuning.md`。
>
> 端节点跑哪些服务、怎么配, 见 rpi 项目的 `docs/service-inventory.md`。
>
> Web 服务的构建期预压缩 (Brotli + Bun) 见 fdm 项目的 `docs/web-precompression.md`。

# 客户端分流规则

以下是客户端配置的强制规则, 不随客户端类型放宽:

- **严禁使用 `AllowedIPs = 0.0.0.0/0`**: 全局代理会让该机器的所有流量借道 VPS 出网, 导致流量账单暴涨。必须仅放行虚拟内网: `AllowedIPs = 10.8.0.0/24`。
- **禁止用 `DNS` 覆盖客户端公共 DNS**: 删除配置中的 `DNS = 223.6.6.6` 一类条目, 防止隧道改写系统 DNS, 导致分流失效或产生 DNS 污染。
- **服务端默认模板固化**: 在 WireGuard 服务端的客户端生成模板里, 把默认 `AllowedIPs` 固化为 `10.8.0.0/24`, 防误发全局配置。

```conf
[Interface]
PrivateKey = EMjggfz5HtuN0qiABWxyz/A9lDqh+8FNQbTmVY6Mf3o=
Address = 10.8.0.5/24, fdcc:ad94:bacf:61a4::cafe:5/112
MTU = 1420

[Peer]
PublicKey = 7wacDJvHhO4gCsTvyuKYeNmRrq7cMvmxlp2YaSakGk4=
PresharedKey = AgGm2QfOVFVlqi2+u386XeRykEET8vq7HRWueXrHOEc=
AllowedIPs = 10.8.0.0/24, fdcc:ad94:bacf:61a4::cafe:0/112 # 仅代理虚拟内网
PersistentKeepalive = 25
Endpoint = 139.196.99.84:31820
```

仅代理 `10.8.0.0/24` (及 IPv6 `fdcc:ad94:bacf:61a4::cafe:0/112`) 网段, 不接管客户端全部流量。

> **承接网关 Nginx 反代的端节点特例 (`rrpi`、`woz`)**: 在网关 `rwpn` 上, `wg-easy` 运行于 Docker 自定义网桥 `10.42.42.0/24` (宿主机网桥 IP 为 `10.42.42.1`), 宿主机 Nginx 反代请求进入 `wg0` 隧道时源 IP 保持为 `10.42.42.1`。因此需要承接网关反代的端节点 (如 `rrpi`、`woz`), 其 `AllowedIPs` 必须额外包含 `10.42.42.0/24` (`AllowedIPs = 10.8.0.0/24, 10.42.42.0/24, fdcc:ad94:bacf:61a4::cafe:0/112`), 否则 WireGuard 会因源地址校验失败而丢弃反代请求。

> **Docker 端口与宿主机原生进程的防火墙路径差异**: Docker 桥接容器发布的端口经 `PREROUTING` DNAT 后走 `FORWARD` 链 (由 `DOCKER-USER` 中的 `-i wg0 -j RETURN` 统一放行); 而宿主机原生进程 (如 `netdata` `:19999`) 与 `network_mode: host` 容器 (`qipao.mongodb` `:9123`、`qipao.redis` `:9697`、`api.qipao.world` `:9323`) 走的是 `INPUT` 链, 必须逐条执行 `ufw allow in on wg0 to any port <端口> proto tcp` 放行, 否则在 `wg0` 内网访问会超时。

## Endpoint 用 IP 还是域名

wg-easy 生成的配置里, `Endpoint` 默认写服务器公网 IP (`139.196.99.84:31820`)。这不构成安全问题。

WireGuard 认的是公钥, 不是 IP: 握手时双方用 Curve25519 交换密钥、用 ChaCha20-Poly1305 加密, 服务端只接受配置里登记过的公钥。知道 Endpoint 地址但没有对应私钥的人, 发包过去会被静默丢弃, 连响应都收不到。这也是为什么 WireGuard 端口被扫描时看起来像「端口开着但没有服务」。

域名只有一个好处: 换服务器 IP 时改 DNS 即可, 不用给所有客户端重发配置。这是可维护性, 不是安全性。域名本身也不是秘密, DNS 查询记录与证书透明度日志都可能暴露它。

真正需要守住的是这四点:

1. **管理面板不暴露公网**: wg-easy 的 `31821/tcp` 绑定 `127.0.0.1`, 通过 SSH 隧道访问, 不要为了省事改回 `0.0.0.0`。
2. **客户端配置按密码对待**: `.conf` 里有私钥与 PresharedKey, 泄露即可冒充该客户端。
3. **服务器本身**: 拿到 root 就能读走全部私钥与配置, 此时 Endpoint 怎么写都无关紧要。
4. **WireGuard 端口**: `31820/udp` 必须对公网开放, 这是协议要求, 不是缺陷。

要改成域名访问时, 把 wg-easy 的 `WG_HOST` 从 IP 改为域名, 生成的配置会自动替换。前提是域名已经解析到该服务器, 否则新客户端连不上。

## 客户端安装与配置

在 wg-easy 里新建客户端后下载它的 `.conf` 文件。三个平台的配置内容完全一样, 区别只在安装方式与导入入口。

### Ubuntu

服务器与桌面通用, 走命令行。

```shell
sudo apt update
sudo apt install -y wireguard

# 把下载的 .conf 放成 wg0.conf。权限必须是 600, 否则 wg-quick 会拒绝加载
sudo install -m 600 下载的客户端.conf /etc/wireguard/wg0.conf

# 启动并设为开机自启
sudo systemctl enable --now wg-quick@wg0

# 查看接口与握手状态
sudo wg show
ip addr show wg0
```

配置文件名与实例名要对应: `/etc/wireguard/wg0.conf` 对应 `wg-quick@wg0`, 如果叫 `server.conf` 就换成 `wg-quick@server`。

### Windows

Windows 有官方图形客户端, 全程鼠标操作, 不需要命令行。

1. 从 [wireguard.com/install](https://www.wireguard.com/install/) 下载官方安装包 (`wireguard-installer.exe`), 双击安装。
2. 打开 WireGuard 客户端, 点左下角「导入隧道」→「从文件导入」, 选中 `.conf` 文件。
3. 也可以点「从剪贴板导入」, 把配置文本直接粘进去。
4. 在隧道列表里点「激活」。激活后隧道名称左侧会出现勾选状态, 系统托盘出现 WireGuard 图标。
5. 点开某个隧道可以看到「最新握手」时间, 显示 `x 秒前` 之类的相对时间即连接成功。

托盘图标可以右键快速激活/停用所有隧道。客户端默认随系统启动, 并在上次退出时的状态恢复连接。

### macOS

macOS 同样有官方图形客户端, 从 App Store 安装即可, 菜单栏常驻。

1. App Store 搜索「WireGuard」安装, 或从官网下载 dmg。
2. 打开 App, 点左下角「+」→「从文件导入隧道」或「从剪贴板导入」, 选中或粘贴 `.conf`。
3. 点隧道右侧的开关激活。激活后菜单栏出现 WireGuard 图标。
4. 点菜单栏图标可以看到各隧道的「最新握手」时间, `x 秒前` 即连接成功。
5. 在 App 的设置里确认「登录时启动」已勾选, 否则重启后不会自动连。

只用命令行、不用图形客户端时, 可以 `brew install wireguard-tools` 后执行 `wg-quick up 配置路径`, 停止用 `wg-quick down 配置路径`。

两个平台的图形客户端都支持一次导入多个隧道 (比如给不同环境各配一个), 用列表切换。导入后配置里的私钥由客户端自己保存, 界面上只能看到公钥。

### 验证

```shell
# 网关
ping -c 3 10.8.0.1

# 树莓派
ping -c 3 10.8.0.3

# 握手是否成功, latest handshake 有时间说明通了
sudo wg show
```

三个平台都只看一条指标: `wg show` 里的 `latest handshake`。显示 `1 minute ago` 之类的相对时间即握手成功; 一直是空或 `Never` 说明没连上。

### 常见问题

- **握手一直是 Never**: 检查 `Endpoint` 的 IP 与端口能不能从客户端网络访问。WireGuard 走 UDP, 用 `nc -u -v 139.196.99.84 31820` 试探, 但即使端口探测没响应也可能是通的, 以 `wg show` 的握手时间为准。
- **能连上但访问不了内网服务**: 首选确认目标服务本身的防火墙放行 (rrpi 走 UFW 白名单), 其次确认 `AllowedIPs` 包含 `10.8.0.0/24`。
- **公网访问变慢或走不了**: 这是预期行为。`AllowedIPs = 10.8.0.0/24` 只接管内网网段, 公网流量仍走本地出口, 不会经过 VPS。
- **开机没自动连**: Ubuntu 上确认 `systemctl is-enabled wg-quick@wg0` 返回 `enabled`; Windows 与 macOS 客户端默认随系统启动, 但要在 App 里确认隧道处于「激活」状态。

## 组网后的安全边界

WireGuard 保证传输安全: ChaCha20-Poly1305 加密、公钥认证、防重放, 隧道里的流量偷不走也篡改不了。

**但它不提供访问控制**。组网成功后所有 peer 在 `10.8.0.0/24` 里互通, 任何一台设备被入侵, 攻击者就能直接扫到其他设备的内网端口。这是横向移动的典型入口。

所以每台设备接入后都要补三件事:

1. **防火墙**: 默认拒绝入站, 只放行真正需要给内网用的端口。按机器实际角色配, 不要照搬其他设备的白名单。
2. **服务绑定**: 能只绑 `127.0.0.1` 的绝不绑 `0.0.0.0`, 能只绑 `wg0` 的不绑全网卡。
3. **密钥可撤销**: 每台设备独立密钥, 某台不用了或疑似泄露, 在 wg-easy 里删掉它的 peer, 其他设备不受影响。

当前各设备的实际状态:

| 设备 | 现状 | 风险 |
| --- | --- | --- |
| rwpn (网关) | wg-easy 管理面板绑 `127.0.0.1`, 经 SSH 隧道访问 | 可控 |
| rrpi (端节点) | UFW 启用, 入站仅 wg0 白名单端口与 SSH; Docker 发布端口经 `FORWARD` 绕开 UFW, 由 `DOCKER-USER` 按 `--ctorigdstport` 逐端口放行 wg0, 物理网卡来源在链尾被 `DROP`; 公网 IPv6 出向由 `ip6-egress-guard` 封堵 | 可控, 白名单内的服务需自身安全; 家庭局域网无法直连任何容器端口; 隧道内也只能访问 14 个白名单端口 |
| 新接入设备 | 默认无限制 | 接入后对所有 peer 开放全部端口, 必须先配防火墙 |

新设备接入时的最小动作:

```shell
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable
ufw status verbose

# 需要给内网提供的服务逐条放行, 且限定 wg0 接口
ufw allow in on wg0 to any port 8080 proto tcp comment 'internal service'
```

一句话: 隧道保证「别人偷不到」, 防火墙保证「内网里的坏人也进不来」。

## 新设备接入执行模板

| 平台 | 模板 | 检查点 |
| --- | --- | --- |
| Linux (Ubuntu) | [`docs/linux-onboarding-prompt.md`](docs/linux-onboarding-prompt.md) | 7 项 |
| Windows | [`docs/windows-onboarding-prompt.md`](docs/windows-onboarding-prompt.md) | 8 项 |

把 `<配置文件内容>` 替换为 wg-easy 生成的客户端配置, 整份交给执行体, 检查点全通过即接入成功。

---
