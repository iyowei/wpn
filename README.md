# WPN

Wireguard 组网。

## 场景

* 10 ~ 50 个客户端节点
* 个人数据中心

## 组网架构：星型架构

目前的场景使用星型架构组网已经足够可用，对地理分布、负载均衡、主备切换方面更高可用需求不大，暂时没有足够的必要性抬升成本去使用网状架构（Mesh）、混合架构。

## 公网服务器

带宽：10～30 Mbps
CPU：2 核
内存：2 GB
硬盘：20 GB

扩容决策树，
```
判断流程：
├── 带宽使用率 > 70%？
│   ├── 是 → 考虑横向扩展（多节点）
│   └── 否 → 继续评估
├── CPU软中断 > 25%？
│   ├── 是 → 优化网卡队列或升级CPU
│   └── 否 → 继续评估
├── 内存使用 > 80%？
│   ├── 是 → 增加内存（通常不是瓶颈）
│   └── 否 → 保持现状
└── 延迟增加？
    └── 是 → 部署区域节点
```

## 服务器设置

- [X] 修改主机名
- [ ] 私钥登录模式
- [ ] 修改 ROOT 密码
- [ ] 创建普通账号
- [ ] 修改 DNS
- [ ] 切换系统更新源
- [ ] Ubuntu 升级内核
- [ ] 更新系统
- [ ] 部署 Docker
- [ ] SSH v8.5 ~ v9.8 高危漏洞修复
- [ ] 修改虚拟内存大小
- [ ] 系统时区调整
- [ ] 安全组 / 防火墙
- [ ] 网络优化，尤其是 UDP
- [ ] 安装 [wg-easy](https://github.com/wg-easy/wg-easy)
- [ ] 计划任务：DNS 刷新
- [ ] 计划任务：重启
- [ ] 计划任务：自检，并通过微信查看自检结果

### 修改主机名

修改（`vim /etc/hostname`）成 “wap” 吧。修改完成后重启（`reboot`）生效。

### 私钥登录模式

在本地计算机生成新的密钥对：
```shell
ssh-keygen -t rsa -b 4096
```

> 私钥不可以分享给本不该访问服务器的任何人！

完整复制公钥内容。

假设当前是为了给 `root` 用户添加公钥身份验证，以 `root` 身份访问服务器，进入用户根目录，创建 `~/.ssh` 目录，如果它不存在：
```shell
cd ~

mkdir .ssh
chmod 700 .ssh
```

将之前从本地复制的完整公钥内容复制到 `~/.ssh/authorized_keys` 文件中：
```shell
vim ~/.ssh/authorized_keys

# 这一步一定不能漏，否则会因为权限或文件模式冲突无法成功验证
chmod 600 ~/.ssh/authorized_keys
```

退出服务器。

往 `~/.ssh/config` 文件中添加：
```
Host 自定义标签
  HostName 服务器 IP 地址
  User root
  IdentityFile ~/.ssh/私钥文件名
  Port 22
```

之后就可以通过秘钥登录服务器了：
```
ssh 自定义标签
```

要为别的用户设置公钥身份验证，同上。

#### 修改 sshd 配置：禁止用密码及 root 账户登录服务器
修改 `/etc/ssh/sshd_config` 配置文件，
```conf
PermitRootLogin no

PermitEmptyPasswords no
PasswordAuthentication no
```

重启 `ssh` 守护进程：
```shell
systemctl reload ssh
```

此时先不要退出当前 SSH 会话，重开一个命令行窗口，尝试用 iyowei 账户登录系统，顺利登录服务器则说明配置成功。

再尝试以 root 身份登录服务器，如果出现如下消息，则说明成功阻止以 root 身份登录系统，
```shell
Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

以 iyowei 身份登录服务器，切换到 root 账户，删除 `~/.ssh/authorized_keys` 文件。

#### 修改端口号
修改 `/etc/ssh/sshd_config` 配置文件，
```conf
Port 59698
```

修改端口号后要生效的话，需执行如下指令，
```shell
systemctl daemon-reload
systemctl restart ssh.socket
```

### 网络优化

执行 `wget -N --no-check-certificate "https://get.2sb.org/https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh`，并选择序号 22 号。

### 安全组 / 防火墙

```shell
# 自定义 SSH 端口号
ufw allow 59698

ufw allow https
ufw allow http

ufw allow 31820
ufw allow 31821
```

## 客户端分流规则

```conf
[Interface]
PrivateKey = EMjggfz5HtuN0qiABWxyz/A9lDqh+8FNQbTmVY6Mf3o=
Address = 10.8.0.5/24, fdcc:ad94:bacf:61a4::cafe:5/112
DNS = 223.6.6.6, 2400:3200:baba::1
MTU = 1420

[Peer]
PublicKey = 7wacDJvHhO4gCsTvyuKYeNmRrq7cMvmxlp2YaSakGk4=
PresharedKey = AgGm2QfOVFVlqi2+u386XeRykEET8vq7HRWueXrHOEc=
AllowedIPs = 0.0.0.0/0, ::/0 # 全局代理
PersistentKeepalive = 25
Endpoint = 47.110.73.199:51820
```

这份配置启用后，效果是 "全局代理"，表示所有流量都通过 WireGuard 隧道。

如果是内网穿透应用场景， 某网服务器 A 若是启用了该配置，以 SSH 流量为例会被重定向到 WireGuard 服务器，只能通过 WireGuard IP 访问，假设 A 是台公网服务器，原本公网 IP 是 `47.110.73.199`，现在没法儿通过 `ssh root@47.110.73.199` 登陆了，根据前述，这台服务器现在只能通过 `10.8.0.4` 这个 WireGuard 隧道 IP 对外通信。

如果这种表现不符合预期，可调整配置为，

```conf
[Interface]
PrivateKey = EMjggfz5HtuN0qiABWxyz/A9lDqh+8FNQbTmVY6Mf3o=
Address = 10.8.0.5/24, fdcc:ad94:bacf:61a4::cafe:5/112
DNS = 223.6.6.6, 2400:3200:baba::1
MTU = 1420

[Peer]
PublicKey = 7wacDJvHhO4gCsTvyuKYeNmRrq7cMvmxlp2YaSakGk4=
PresharedKey = AgGm2QfOVFVlqi2+u386XeRykEET8vq7HRWueXrHOEc=
AllowedIPs = 10.8.0.0/24 # 分流
PersistentKeepalive = 25
Endpoint = 47.110.73.199:51820
```

仅代理 `10.8.0.0/24` 网段。