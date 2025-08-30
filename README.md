# WPN

Wireguard 组网。

## 项目主要组成部分

- [X] 文档
- [X] 自动化脚本
- [X] 配置文件

## 网关服务器

参见 SERVER.md 。

## 端节点

参见 PEER.md 。

## 快速部署

准备需要放到 WireGuard 网管服务器上的文件，
```shell
git clone git@github.com:iyowei/wpn.git
cd wpn

make pack
```

将压缩包以及 "wpn-zip-handler.sh" 拷贝到目前 WireGuard 网关服务器上的指定磁盘位置。

登录 WireGuard 网关服务器并进入压缩包所在位置处理压缩包，
```shell
# 用来处理压缩包，包括解压缩、更新压缩包内脚本文件为可执行文件等操作
bash ./wpn-zip-handler.sh
```

进入压缩包解压后的文件夹，
```shell
# 输入 "Server酱" 发送密钥
vim .env

make install
```
