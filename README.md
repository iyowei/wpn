# WPN

Wireguard 组网。

> 主机底座 (系统初始化、内核调优、安全基线、Docker、主机级定时任务、证书) 已迁至 server-forge 项目, 见其 `docs/host-bootstrap.md`。本仓库只保留 WireGuard 组网与网关 nginx。

## 项目主要组成部分

- [X] 文档
- [X] 自动化脚本
- [X] 配置文件

## 网关服务器

参见 SERVER.md 。

## 端节点

参见 PEER.md（包含客户端分流规则与树莓派端节点高性能网络栈调优）。

## 极致省流检查清单

客户端规则见 PEER.md; 主机层条目见 server-forge 的 `docs/host-bootstrap.md`; Nginx 兜底拦截门见 nginx-forge 的 `docs/nginx-setup.md`。

## 核心配置沉淀

- **网关隧道路由与 MSS 钳制**: `etc/rc.local`
- **网关穿透子域名实例**: `etc/nginx/sites-available/fdm.qipao.world.conf` (上游为 WireGuard 内网端节点)
- **WireGuard 容器**: `etc/docker/containers/wg-easy/docker-compose.yml`

> 通用 Nginx 配置 (proxy、compression、WebSocket 映射、默认拦截门、systemd 单元) 见 nginx-forge 项目。

## 快速部署

准备需要放到 WireGuard 网管服务器上的文件,
```shell
git clone git@github.com:iyowei/wpn.git
cd wpn

make pack
```

将压缩包以及 `scripts/wpn-zip-handler.sh` 拷贝到目前 WireGuard 网关服务器上的指定磁盘位置。

登录 WireGuard 网关服务器并进入压缩包所在位置处理压缩包,
```shell
# 用来处理压缩包，包括解压缩、更新压缩包内脚本文件为可执行文件等操作
bash ./scripts/wpn-zip-handler.sh
```

进入压缩包解压后的文件夹,
```shell
# 输入 "Server酱" 发送密钥
vim .env
```

**前提**: 目标机器已执行 server-forge 的主机底座装配 (`make install`), Docker 与安全基线就绪。

```shell
make install
```
