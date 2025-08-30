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

## 快速开始

克隆项目后，运行 `make pack` 指令，然后将压缩包以及 "wpn-zip-handler.sh" 拷贝到服务器上指定位置。

"wpn-zip-handler.sh" 脚本是用来方便处理这个压缩包的，包括解压缩、更新脚本文件为可执行文件等操作。
