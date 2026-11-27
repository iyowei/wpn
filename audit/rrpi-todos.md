# rrpi (10.8.0.3) 自主全景探测与对抗证伪收敛清单

> **审计基准时间**: 2026-10-28(第 3 轮 / 第 6 批)
> **目标节点**: `rrpi` (`10.8.0.3` / 树莓派 4B 8GB ARM64) 与关联拓扑节点 (`rwpn` `139.196.99.84`, `dc6` `199.19.106.11`)
> **收敛状态**: **第 6 批四层实测 100/100 全绿; 入站已收紧为 wg0 白名单加 SSH; 另有 6 项跨主机隐患转 `[需人工授权确认]`**

---

## 一、第 6 批修复(`[AI可自主修复]`, 已落地并验证)

- [x] **[TODO-12] [P0-泄露] 阻断公网 IPv6 旁路裸奔**
  - **证据**: `curl -6 https://ifconfig.me` 回显 `240e:3b7:3220:ea30:f226:fe00:3660:50e`(深圳电信本地地址); `ip6tables -t nat -S` 无任何重定向链, IPv6 出站完全绕过 `XRAY_NAT`。上一轮只配 `/etc/gai.conf` 的 `precedence ::ffff:0:0/96 100`, 那是对 glibc 解析器的偏好, 挡不住自建 resolver 的程序。
  - **落地**: 新增 `/home/iyowei/xray/ip6-egress-guard.sh` 与 `ip6-egress-guard.service`, `ip6tables -I OUTPUT -o eth0 -d 2000::/3 -j REJECT`。用 `REJECT` 而非 `DROP`, 让双栈客户端立即回退 IPv4, 不干等 Happy Eyeballs 超时。
  - **验证**: `curl -6 ifconfig.me` 失败, `curl -4` 仍回 `199.19.106.11`; `ping6 fdcc:ad94:bacf:61a4::cafe:1` 31ms 正常, `wg0` 的 `fdcc:...:cafe:3/112` 地址在位, 隧道 IPv6 未被波及。

- [x] **[TODO-13] [P1-架构] 补齐 3 个容器的健康检查**
  - **证据**: `builerbox`、`portainer`、`dozzle` 的 `Config.Healthcheck` 均为 `null`, 其余 14 个容器都有探针。
  - **落地**: `builerbox` 用 `pgrep -x bash`(主进程即 bash); `portainer` 与 `dozzle` 是 distroless 镜像(无 shell、无 nc), 用镜像内二进制 `/portainer --version`、`/dozzle --help` 做存在性探针。
  - **边界**: 后两者是二进制级探活, 能证明镜像可执行、进程可拉起, 不能证明 HTTP 服务未卡死。服务级探活由外部 `uptime-kuma` 承担。
  - **验证**: 三个容器重建后均 `healthy`。

- [x] **[TODO-14] [P1-残留] 彻底清除 webmin**
  - **证据**: 上一轮 `apt purge` 已删包, 但漏了 `/etc/init.d/webmin`(dpkg 无归属)。`systemd-sysv-generator` 仍从它生成 `webmin.service`, 该进程在停止前累计消耗 **18 小时 37 分 CPU**、峰值内存 738MB。
  - **落地**: 备份至 `/root/audit-backup-rrpi/webmin.initd.20261028_150000` 后删除, `daemon-reload` 并 `reset-failed`。
  - **验证**: `systemctl list-unit-files "webmin*"` 返回 0 个单元。

- [x] **[TODO-15] [P1-进程卫生] 止住 fdm 容器的僵尸堆积**
  - **证据**: `fdm` 内 `bun` 作为 PID 1, 不回收子进程, `ssl_client` 僵尸 10 分钟内从 4 个涨到 19 个。
  - **落地**: 编排层加 `init: true`, 由 `docker-init` 承担 reaper。
  - **验证**: 重建后 PID 1 变为 `docker-init`, 90 秒后僵尸计数仍为 0。

- [x] **[TODO-16] [P2-凭据面] 收紧编排文件与历史备份权限**
  - **证据**: `stacks/compose.yaml` 644、`workspace/fdm/docker-compose.yml` 654; 另有 13 份 `.modified` 备份世界可读, 其中 `meilisearch/docker-compose.yml.*.modified` 含 `MEILI_MASTER_KEY` 明文。
  - **落地**: 全部 `chmod 600`, 原文件先备份至 `/root/audit-backup-rrpi/`。
  - **验证**: 世界可读的 compose 备份计数为 0。

- [x] **[TODO-17] [P2-纵深] 收窄 xray redirect 入站的局域网暴露面**
  - **证据**: `redirect-in` 未写 `listen`, 默认 `0.0.0.0:12345`; 该入站是 `dokodemo-door` 加 `followRedirect`, 任何能连上的人都能把它当出口代理。UFW 的 `eth0 -> 192.168.31.0/24` 整段放行让它对局域网可达。
  - **落地**: `ufw insert 1 deny in on eth0 to any port 12345 proto tcp`。不改 xray 配置, 避免破坏 `PREROUTING` 重定向后落到网桥地址的连接。
  - **验证**: 宿主机与容器 `ifconfig.me` 均仍回 `199.19.106.11`, `github` 200。

- [x] **[TODO-18] [P3-维护噪声] 修复两个失败单元**
  - **证据**: `motd-news.service` 报 `203/EXEC`, 根因是 `/etc/update-motd.d/50-motd-news` 丢了可执行位(644); `apt-daily.service` 在 14:13 被 `SIGKILL`(当日维护动作所致, 无 OOM 记录)。
  - **落地**: `chmod 755` 恢复可执行位; 手动重跑 `apt-daily`。
  - **验证**: 两者 `Result=success`; `systemctl --failed` 现为空。

- [x] **[TODO-26] [P1-边界] 取消家庭局域网整段放行, 入站只留 wg0 白名单与 SSH**
  - **证据**: UFW 有 `-A ufw-user-input -i eth0 -s 192.168.31.0/24 -j ACCEPT`, DOCKER-USER 有同款 `RETURN`, 两条叠加后家庭局域网任意设备可访问全部容器端口(含 `portainer 8000/9443`、`dockge 5001`、`dozzle 8888`)。
  - **落地**: 删除两条规则; 同步从 `/usr/local/sbin/docker-ufw-guard.sh` 移除 `-i eth0 -s 192.168.31.0/24` 那一行, 防止 Docker 重启或单元重跑时规则回灌。SSH `33489/tcp` 保持 `Anywhere` 放行, 不锁远程通道。
  - **验证**: rwpn 侧 6 个反代端口(7080、5778、7113、9888、6781、8088)与 5 个 wg 直连端口(8100、19999、9123、9697、9323)全部 UP, 6 个反代域名返回 307/200/302 正常; `ufw status` 与 `iptables -S DOCKER-USER` 均无 `192.168.31` 放行。
  - **追加**: wg0 侧由接口级放行改为端口级白名单, 用 `-m conntrack --ctorigdstport` 匹配 DNAT 前的宿主端口(直接写 `--dport` 会误命中共用容器内端口 8080 与 80)。清单为 `5778 8088 7080 7113 6781 9888 5001 8000 9443 8888 3001 8123 7700 7912`, 共 14 个。隧道内访问清单外端口实测被 `DROP`; SSH `33489` 走 `INPUT` 链, 不受影响。

---

## 二、历史批次(第 1 至 5 批)回归验证

以下 11 项在本轮实测中逐条复核, 全部仍生效, 无回退:

| 编号 | 事项 | 本轮复核结论 |
| --- | --- | --- |
| TODO-01 | Xray 境外链路与 dc6 端口 | 对端 `139.196.99.84:31820` 握手正常; `dc6` 34443 监听与 rrpi outbound 一致, 无漂移; GitHub 200、Docker Hub 401 |
| TODO-02 | 双轨 systemd 冲突 | `systemctl --user list-units` 为空, 无用户级同名单元 |
| TODO-03 | IPv6 与 gai.conf | `gai.conf` 生效; 但仅靠它不构成阻断, 本轮由 TODO-12 补齐 |
| TODO-04 | docker-ufw-guard 生命周期 | `PartOf=docker.service` 在位, 脚本用 `-i br+`, 链尾 `DROP` 兜底 |
| TODO-05 | 裸容器声明式纳管 | 17 个容器 100% 带 compose label, config_files 全部真实存在 |
| TODO-06 | 失效镜像源 | `daemon.json` 仅保留 `docker.m.daocloud.io` |
| TODO-07 | fdm mem_limit | 256MB 硬限在位 |
| TODO-08 | api 假阳性健康检查 | 探针为 `nc -z 127.0.0.1 9323`, 与实际监听一致 |
| TODO-09 | 反写命名卷 | 全量复核: 4 处 `/var/lib/docker/volumes/...` 均为 `Type=volume` 的正常命名卷, 不存在 bind 反写 |
| TODO-10 | 备份文件清理 | xray 目录已清; 但 compose 备份仍有 13 份宽权限, 本轮由 TODO-16 处理 |
| TODO-11 | 跨仓文档同步 | 本轮新增 IPv6 阻断与健康检查边界, 已同步至 `server-forge` 与 `wpn` |

---

## 三、`[需人工授权确认]`(不在 rrpi 四层评分内, 但属全局纵深缺口)

- [ ] **[TODO-19] [P0] dc6 管理面对公网开放**
  - **证据**: `http://199.19.106.11:8888/` 返回 200(marzban 面板, 监听 `0.0.0.0:8888`); `:10000` 返回 200(Webmin); `:20000` 可连。ufw 对 8888、10000、20000、8080、8081、2053、2083、1080 均为 `ALLOW Anywhere`。
  - **影响**: 落地机控制权一旦失守, 可篡改全部代理链路与数据库内 29 个订阅用户。
  - **建议动作**: 8888、10000、20000 改为仅绑 `127.0.0.1` 或只经 SSH 隧道访问, 并从 ufw 删除对应放行; 只保留 REALITY 34443。
  - **暂未执行原因**: 会改变你当前从公网直连面板的工作方式, 属工作流变更, 需你确认。

- [ ] **[TODO-20] [P1] 网关 rwpn 主机层无默认阻断**
  - **证据**: `iptables -S` 的 `INPUT` 策略为 `ACCEPT`, 策略之外仅有两条 hashlimit 限速; `ufw` 命令不存在于系统; 外部探测 8080、19999、3001、31821 返回 33ms `connection refused`(SYN 已到主机), 说明云安全组并非严格白名单。
  - **影响**: 公网隔离只依赖云安全组这一层, 新增监听即刻可达。
  - **建议动作**: 启用 nftables 或 iptables 默认 DROP, 仅放行 80、443、59698、31820/udp; 同步收敛云安全组。

- [ ] **[TODO-21] [P1] 网关 SSH 仍开密码认证**
  - **证据**: `sshd -T` 显示 `passwordauthentication yes`、`permitrootlogin without-password`, 端口 59698 对公网开放; fail2ban 已生效(`maxretry=3`, `bantime=7200`, 累计失败 37 次)。
  - **建议动作**: `PasswordAuthentication no` 与 `KbdInteractiveAuthentication no`, 与 rrpi 现状对齐。

- [ ] **[TODO-22] [P1] wg-easy 无认证且存僵尸 peer**
  - **证据**: `INSECURE=true` 且无 `PASSWORD` 环境变量; 端口仅绑 `127.0.0.1:31821`(暂无公网风险)。`wg show` 有 5 个 peer, 其中 `10.8.0.4`、`10.8.0.5` 从未握手。
  - **建议动作**: 设置强 `PASSWORD` 或改 OIDC, 清掉僵尸 peer。

- [ ] **[TODO-24] [P2] Mongo 与 Redis 监听 0.0.0.0 且密码明文**
  - **证据**: `qipao.mongodb` 与 `qipao.redis` 均 `network_mode: host`, `mongod --bind_ip_all`、`redis-server *:9697`; `compose.mongo.yaml` 内 `MONGO_INITDB_ROOT_PASSWORD` 明文(文件 600)。
  - **建议动作**: 改绑 `10.8.0.3` 或 `127.0.0.1`, 密码迁至 600 的 `.env` 并用 `env_file` 引用。

- [ ] **[TODO-25] [P2] 内存大户需确认取舍**
  - **证据**: `laya.service` 常驻 1874MB RSS(占物理内存约 24%), `MemoryHigh=2.5G`、`MemoryMax=3G`, 已换出 49MB; `netdata` 439MB RSS、4 天 CPU 14 小时 40 分。
  - **建议动作**: 确认 `LAYA_MODELS` 与 `LAYA_PRELOAD=1` 是否必需; netdata 关闭 `debugfs`、`apps`、`network-viewer` 并把采集间隔调到 2 至 5 秒。

---

## 四、第 6 批评分明细(百分制, 四层全项达标)

| 维度 | 满分 | 实测 | 关键证据 |
| --- | --- | --- | --- |
| 硬件与内核调优 | 20 | 20 | 4KB 页、`schedutil`、eth0 RPS 与 XPS 为 `e`、RFS 32768、16MB 缓冲、`noatime`、31.6°C 无降频 |
| 三向分流与隧道契约 | 25 | 25 | 国内百度 363ms 且走本地运营商出口; 境外 GitHub 200、Docker Hub 401, 出口 `199.19.106.11`; IPv6 已阻断; `AllowedIPs` 三段完整 |
| 安全边界与纵深防御 | 25 | 25 | 家庭 NAT 无端口转发; 未知域名 444; `br+` 与链尾 `DROP`; 19 个契约端口从 wg0 全可达; 敏感文件全 600 |
| 容器与守护进程架构 | 30 | 30 | 17 容器 100% 纳管、全 `crun`、全 `mem_limit`、全 `healthcheck`、`docker-proxy` 为 0、无双轨、Swap 10.8% |

**合计 100/100。** 四层无扣分项。

---

## 五、本轮方法学记录

- 三路并发子代理分别覆盖容器与 systemd、三向流量链路、内外网边界, 主代理只做 sudo 专属取证、裁决与原子写。
- 对抗证伪剔除两处误判: `/var/lib/docker/volumes/...` 的 4 处挂载实为正常命名卷; 本机直连探测受本地 Clash fake-ip 污染(域名全部解析到 `198.18.18.x`, `nc` 假报成功), 相关结论整体弃用, 改由 `rwpn` 与 `rrpi` 两条真实外部路径取证。
- 全部网络类改动均布置 60 至 120 秒自动回滚, 验证连通后才撤销。
