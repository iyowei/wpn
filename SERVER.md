# 网关服务器

更偏好 "集线器" 这个叫法.

当前方案针对 "个人 / 小型数据中心"、"10 ~ 50 个客户端节点" 设计.

> 主机底座的装配 (系统初始化、内核调优、安全基线、Docker、证书) 见 server-forge 项目的 docs/host-bootstrap.md.

## 组网架构: 星型架构

目前的场景使用星型架构组网已经足够可用, 对地理分布、负载均衡、主备切换方面更高可用需求不大, 暂时没有足够的必要性抬升成本去使用网状架构（Mesh）、混合架构。

## 安全组 / 防火墙

### 边缘节点（rrpi / Peer）防火墙与端口白名单访问控制

边缘单板节点（如 `rrpi`）通过 UFW 严格实施网络隔离策略:
1. 默认入站拒绝 (`default deny incoming`), 默认出站放行 (`default allow outgoing`)。
2. 允许管理端口 SSH（`33489/tcp`）与物理局域网全放行（`eth0` 来源 `192.168.31.0/24`）。
3. 对 WireGuard 隧道（`wg0`, 即网关 `rwpn` 与 WPN 客户端网络）仅白名单放行特定容器服务端口, 其余未授权特权面板（如 Webmin、Portainer、Dockge、Dozzle 等）默认拦截。

落地脚本: `opt/wpn/scripts/firewall-rrpi.sh`。新增业务端口时只改脚本顶部的 `WG_PORTS` 数组, 不要手工执行 `ufw allow`, 否则下次跑脚本会被 `--force reset` 清掉。

```shell
sudo ./opt/wpn/scripts/firewall-rrpi.sh

# 或通过 Makefile
sudo make firewall-setup
```

> Docker 容器会绕过 UFW 规则, 需要配合 server-forge 项目的 `usr/local/sbin/docker-ufw-guard.sh` 兜底。

## 网关端口级限速

限制 WireGuard 端口连接频率:

```shell
sudo iptables -A INPUT -p udp --dport 31820 -m hashlimit \
    --hashlimit-above 10/min --hashlimit-burst 5 \
    --hashlimit-mode srcip --hashlimit-name wg_limit \
    -j DROP
```

防止 SYN Flood,
```shell
sudo iptables -A INPUT -p tcp --syn -m hashlimit \
    --hashlimit-above 1/s --hashlimit-burst 3 \
    --hashlimit-mode srcip --hashlimit-name syn_limit \
    -j DROP
```

## 安装 WireGuard

使用 [wg-easy](https://github.com/wg-easy/wg-easy) 进行中心、可视化 WireGuard 管理。

- `docker pull ghcr.io/wg-easy/wg-easy:15`, 预先拉取镜像;

- `mkdir -p /etc/docker/containers/wg-easy`, 创建存放 wg-easy docker compose 配置文件的地方;

- `cd /etc/docker/containers/wg-easy` 切换到该目录, 将 "iyowei/wpn" 项目里的 "etc/docker/containers/wg-easy/docker-compose.yml" 拷贝过来;

- `docker compose up -d --pull always`, 启动可视化 WireGuard 管理 Web 服务。

### 故障排查: 创建客户端报 Server Error

**症状**: 在 Web UI 点「新建客户端」, 弹窗显示 `发生错误 / Server Error`, 浏览器网络面板里 `/api/client` 返回 500。

**原因**: wg-easy v15 起把配置存进 SQLite (卷内 `wg-easy.db`), 若干字段以 JSON 文本保存。只要其中一个字段不是合法 JSON, 每次读取整张表都会 `JSON.parse` 失败, 新建客户端直接 500。常见坏字段是 `user_configs_table.default_allowed_ips`, 值形如 `[10.8.0.0/24,fdcc:ad94:bacf:61a4::/112]` (地址没加引号)。

**定位**:

```shell
# 看容器日志, 错误栈里会点名 JSON.parse 失败
docker logs wg-easy --tail 60 2>&1 | grep -B2 -A5 "JSON.parse\|SyntaxError"

# 直接查库, 找出不合法的字段
python3 - <<'PY'
import sqlite3, json
db = '/var/lib/docker/volumes/wg-easy_etc_wireguard/_data/wg-easy.db'
conn = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
for t in [r[0] for r in cur.fetchall()]:
    cur.execute(f"PRAGMA table_info({t})")
    cols = [c[1] for c in cur.fetchall()]
    cur.execute(f"SELECT * FROM {t}")
    for i, row in enumerate(cur.fetchall()):
        for col, val in zip(cols, row):
            if isinstance(val, str) and val[:1] in '[{':
                try:
                    json.loads(val)
                except Exception as e:
                    print(f"{t} row {i} col {col}: {e} -> {val[:120]}")
PY
```

**修复**:

```shell
# 1. 备份数据库
cp /var/lib/docker/volumes/wg-easy_etc_wireguard/_data/wg-easy.db \
   /root/wg-easy.db.$(date +%Y%m%d_%H%M%S).bak

# 2. 停容器, 避免运行中的进程把内存里的旧值写回
docker stop wg-easy

# 3. 把坏字段改成合法 JSON (按实际值调整地址)
python3 - <<'PY'
import sqlite3, json
db = '/var/lib/docker/volumes/wg-easy_etc_wireguard/_data/wg-easy.db'
conn = sqlite3.connect(db)
conn.execute("UPDATE user_configs_table SET default_allowed_ips = ?",
             (json.dumps(["10.8.0.0/24", "fdcc:ad94:bacf:61a4::/112"]),))
conn.commit()
print(conn.execute("SELECT default_allowed_ips FROM user_configs_table").fetchall())
conn.close()
PY

# 4. 启动并验证
docker start wg-easy
docker ps --filter name=wg-easy --format '{{.Names}} {{.Status}}'
```

**预防**: 不要在数据库里手写数组值, 要带引号写成合法 JSON, 更稳的做法是在 Web UI 里改默认配置。升级 wg-easy 前先备份整个 `wg-easy_etc_wireguard` 卷。


## 网关 Nginx 专属配置

> 通用装配与调优 (编译安装、systemd、HTTP/3、压缩、缓存) 见 nginx-forge 项目的 docs/nginx-setup.md。
> 本节只保留网关特有的部分。

### 5. 高性能反向代理调优规范 (网关专属部分)

#### ④ 隧道路由 MTU 锁定与 MSS 钳制 (防止大包分片)

网关发往 WireGuard 子网的数据包若继承 Docker 网桥的默认 MTU 1500, 在通过 1420 MTU 的隧道时会触发隐式分片或丢包。

在网关执行并写入 `/etc/rc.local`（参考 `etc/rc.local`）:

```shell
ip route change 10.8.0.0/24 via 10.42.42.42 mtu 1420 advmss 1380
```

- **机制与效果**: 强制本地向端节点发起连接时直接宣告 1380 字节的最大报文段长, 杜绝跨隧道传输产生任何 IP 分片。


#### ⑦ 端到端源头预压缩架构设计 (跨网省流 70%)

在跨公网穿透架构中, 若只依赖网关 Nginx 实时动态压缩, 数据包在「端节点 ➔ WireGuard 隧道 ➔ 网关」的整段内网链路中依然在跑几十甚至上百 KB 的未压缩明文, 白白浪费隧道带宽。

标准实现是将预压缩前置到**前端代码构建 / Docker 镜像打包阶段**（详见 `PEER.md` 落地模板）:
1. **源头预先压缩**: 在构建期使用 Brotli Level 11 生成静态 `.br` 镜像;
2. **端节点容器直吐**: 容器内 Web 服务（如 Bun `serve.js`）感知 `Accept-Encoding: br` 并直接从内存/磁盘吐出预压缩文件, 携带 `Content-Encoding: br`;
3. **隧道流量暴减**: 跨网隧道从源头就只传输微小数据包（如 126 KB JS 脚本在隧道内仅跑 39 KB, 体积暴降近 70%）;
4. **全链路零算力消耗**: 端节点不计算、网关 Nginx 不计算, 全链路纯静态透传。


### 6. 网关穿透子域名路由映射与安全策略

针对缺乏强身份认证、涉及个人数据索引或模型计算资源的基础服务（如 Meilisearch、Laya、Spoolman、Netdata、Dozzle）, **一律不开启公网反向代理**, 从根源消除未授权扫描、计算资源盗用与删库风险:
- **纯内网访问基准**: 服务仅绑定于 WireGuard 虚拟内网 `10.8.0.3`（端节点）; 客户端通过接入 WireGuard 隧道进行安全调用。
- **网关未匹配阻断**: 公网针对此类域名的任意请求均由 `00-default.conf` 直接切断（`return 444`）。


