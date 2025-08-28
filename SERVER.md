# 网关服务器

更偏好 "集线器" 这个叫法。

当前方案针对 "个人 / 小型数据中心"、"10 ~ 50 个客户端节点" 设计。

## 目录

- [X] 组网架构：星型架构
- [X] 服务器配置
- [X] 修改主机名
- [X] 创建普通账号
- [X] 私钥登录模式
- [X] 修改 ROOT 密码
- [X] 修改 DNS
- [X] 切换系统更新源
- [X] 升级内核
- [X] 更新系统
- [X] 准备 Docker
- [X] SSH v8.5 ~ v9.8 高危漏洞修复
- [X] 虚拟内存
- [X] 系统时区
- [X] 网络优化
- [X] 安全组 / 防火墙
- [X] 防暴力破解
- [X] DDoS 防护
- [X] 安装 WireGuard
- [ ] 计划任务：DNS 刷新
- [ ] 计划任务：重启
- [ ] 计划任务：自检，并通过微信查看自检结果

## 组网架构：星型架构

目前的场景使用星型架构组网已经足够可用，对地理分布、负载均衡、主备切换方面更高可用需求不大，暂时没有足够的必要性抬升成本去使用网状架构（Mesh）、混合架构。

## 服务器配置

有公网 IP。

带宽：10 ～ 30 Mbps
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

## 修改主机名

修改（`vim /etc/hostname`）成 “wap” 吧。修改完成后重启（`reboot`）生效。

## 创建普通账号

新部署的 Ubuntu 系统默认提供了 “ubuntu” 用户或者 "root" 用户登录系统，但如果没有的话，可以通过如下办法创建用户。

假设需要创建的用户叫 `iyowei`，

```shell
adduser iyowei

# 为用户 `iyowei` 设置密码，一般在执行 `adduser` 指令时会提示输入密码
passwd iyowei

# 查看是否创建了 iyowei 账户
cat /etc/passwd

# 或
cut -d: -f1 /etc/passwd
```

在 Ubuntu 系统中，如果你希望用户可以通过在每个命令前加上 `sudo` 来以管理员权限操作，需要将该用户添加到有 `sudo` 权限的组（通常是 `sudo` 组），并确保 `/etc/sudoers` 文件配置正确。Ubuntu 默认已经为 `sudo` 组成员提供了这种能力，因此操作很简单。

- [ ] 执行 `whoami` 获取当前用户名，假设是 `iyowei`，执行 `groups iyowei` 检查用户所属组，如果输出中包含 `sudo`，说明该用户已经有权限，无需进一步操作
- [ ] Ubuntu 默认通过 `sudo` 组授予用户使用 `sudo` 的权限。以 root 或已有 sudo 权限的用户执行 `sudo usermod -aG sudo iyowei`,`-a` 表示追加组，`-G` 指定组名
- [ ] 执行 `groups iyowei` 验证是否将 `iyowei` 添加到 `sudo` 组，确保输出中包含 `sudo`，即 `iyowei` 已被添加到 `sudo` 组
- [ ] 假设到这一步你在 `root` 账户下，可以切换到 `iyowei` 用户下，执行 `sudo apt update -y`，如果输入密码后正常开始更新，那就说明设置成功了
- [ ] Ubuntu 默认配置中，`sudo` 组已有权限，但可以检查确认 `/etc/sudoers` 中是否包含 `%sudo   ALL=(ALL:ALL) ALL`，`%sudo`：表示 `sudo` 组，`ALL=(ALL:ALL) ALL`：组内用户可在所有主机上以任意用户身份执行所有命令，没有就加上

添加用户到 `sudo` 组后，他们可以执行任何 root 命令（如 `sudo rm -rf /`），请谨慎选择用户。

默认每次用 `sudo` 需要输入用户密码。如果想免密码，可以在 `sudoers` 中添加 ` <username> ALL=(ALL) NOPASSWD: ALL`，如 `iyowei ALL=(ALL) NOPASSWD: ALL`，但不推荐，降低安全性。

Ubuntu 用 `sudo` 组，Red Hat 系（如 CentOS）用 `wheel` 组，配置类似。

如果 `sudo` 组被删除（极少见），可以用 `groupadd sudo` 创建，再配置 `sudoers`。

现在可以切换到 iyowei 账户了：

```shell
su iyowei
```

退出当前 SSH 会话，尝试以 iyowei 的身份登录服务器。

## 私钥登录模式

如果本地已经有可用的密钥，可调过下述创建密钥的过程。

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

### 修改 sshd 配置：禁止用密码及 root 账户登录服务器

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

### 修改端口号

修改 `/etc/ssh/sshd_config` 配置文件，

```conf
Port 59698
```

修改端口号后要生效的话，需执行如下指令，

```shell
systemctl daemon-reload
systemctl restart ssh.socket
```

或者重启。

下次登录如果遇到登录超时问题，可以看下安全组或者防火墙规则里是否包含 59698 端口的入方向访问规则。

## 修改 ROOT 密码

一般可以在创建实例时就设置好 "root" 密码。

## 修改 DNS

执行 `bash <(curl -sL kejilion.sh)` 使用 kejilion.sh 脚本操作。

## 切换系统更新源

我使用了[阿里巴巴开源镜像站](https://developer.aliyun.com/mirror/)，或者也可以选择 [清华大学开源软件镜像站](https://mirrors.tuna.tsinghua.edu.cn)、[科大镜像站](https://mirrors.ustc.edu.cn/help/index.html) 等，相关设置改成（`vim /etc/apt/sources.list`）如下即可，

```
# The official image http://ports.ubuntu.com/ubuntu-ports

# See http://help.ubuntu.com/community/UpgradeNotes for how to upgrade to
# newer versions of the distribution.
deb https://mirrors.aliyun.com/ubuntu-ports jammy main restricted

## Major bug fix updates produced after the final release of the
## distribution.
deb https://mirrors.aliyun.com/ubuntu-ports jammy-updates main restricted

## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu
## team. Also, please note that software in universe WILL NOT receive any
## review or updates from the Ubuntu security team.
deb https://mirrors.aliyun.com/ubuntu-ports jammy universe
deb https://mirrors.aliyun.com/ubuntu-ports jammy-updates universe

## N.B. software from this repository is ENTIRELY UNSUPPORTED by the Ubuntu
## team, and may not be under a free licence. Please satisfy yourself as to
## your rights to use the software. Also, please note that software in
## multiverse WILL NOT receive any review or updates from the Ubuntu
## security team.
deb https://mirrors.aliyun.com/ubuntu-ports jammy multiverse
deb https://mirrors.aliyun.com/ubuntu-ports jammy-updates multiverse

## N.B. software from this repository may not have been tested as
## extensively as that contained in the main release, although it includes
## newer versions of some applications which may provide useful features.
## Also, please note that software in backports WILL NOT receive any review
## or updates from the Ubuntu security team.
deb https://mirrors.aliyun.com/ubuntu-ports jammy-backports main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu-ports jammy-security main restricted
deb https://mirrors.aliyun.com/ubuntu-ports jammy-security universe
deb https://mirrors.aliyun.com/ubuntu-ports jammy-security multiverse
```

如果有增加其它软件源的需求，放在 `/etc/apt/sources.list.d` 目录下即可。

## 升级内核

切换到 "root" 账号。

安装 "ubuntu-mainline-kernel.sh" 内核升级工具，

```shell
wget https://get.2sb.org/https://raw.githubusercontent.com/pimlie/ubuntu-mainline-kernel.sh/master/ubuntu-mainline-kernel.sh

chmod +x ubuntu-mainline-kernel.sh

mv ubuntu-mainline-kernel.sh /usr/local/bin/
```

执行 `ubuntu-mainline-kernel.sh -c` 检查可升级版本。

假设可升级版本为 "v6.16.3"，执行 `ubuntu-mainline-kernel.sh -i v6.16.3` 即可开始升级。

内核升级完成后，重启系统。

执行 `uname -r` 检查内核版本，如果是 "v6.16.3" 版本则说明升级已完成。

## 更新系统

执行 `sudo apt update && sudo apt upgrade -y` 即可。

## 准备 Docker

切换到 "root" 账号。

依次执行下述指令，

```shell
apt remove docker docker-engine docker.io containerd runc

apt update

apt install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Docker 官方源
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 或使用清华大学 TUNA 镜像站
# 国内镜像站通常直接同步官方源内容
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu  \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 或使用中国科学技术大学 (USTC) 镜像站
# 国内镜像站通常直接同步官方源内容
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu  \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 或使用阿里云镜像站
# 国内镜像站通常直接同步官方源内容
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.aliyun.com/docker-ce/linux/ubuntu  \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update

apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

也可以先用 Docker 官方软件源安装好之后，再执行 `bash <(curl -sSL https://linuxmirrors.cn/main.sh)` 自动更换 Docker 软件源。

Docker 守护进程默认使用了 upstart 的系统启动，所以配置 DockerHub 中科大镜像站时，需要到配置文件 `/etc/default/docker`中配置 `DOCKER_OPTS` 选项，

```
DOCKER_OPTS="--registry-mirror=https://docker.lixd.xyz/"
```

或者修改 Docker 的静态配置，通常存储在 `/etc/docker/daemon.json` 文件，

```json
{
  "registry-mirrors": [
    "https://do.nark.eu.org",
    "https://dc.j8.work",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://docker.nju.edu.cn",
    "https://docker.lixd.xyz/"
  ]
}
```

重启 Docker 守护进程，

```shell
service docker restart
```

检查新配置的镜像是否启用，

```shell
docker info --format '{{.RegistryConfig.Mirrors}}'
```

检查当前 Docker 的所有信息，

- [ ] 可通过 `service --status-all` 指令查看所有使用了 upstart 系统启动的服务
- [ ] 执行 `docker info` 查看运行时配置
- [ ] 执行 `cat /etc/docker/daemon.json` 查看 Docker Daemon 静态配置文件
- [ ] 执行 `systemctl cat docker` 查看 Docker 服务文件
- [ ] 执行 `ps aux | grep dockerd` 查看 Docker 启动参数

检查 Docker 是否安装成功。

在主目录创建一个名为 “ti” 的文件夹（`mkdir ti`），在里头（`cd ti`）创建如下 Dockerfile，

```
FROM node
ENV NODE_ENV=production
RUN npm i -g serve
COPY . /
EXPOSE 6789
CMD [ "serve", "-l", "6789" ]
```

构建成镜像，

```shell
docker build . -t ti:latest
```

运行容器，

```shell
docker run -d --restart on-failure --name ti -p 6789:6789 ti
```

获取当前服务器在内网的 IP，

```shell
ip addr show | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | grep "^192"
```

满足以下条件说明 Docker 成功安装，

- [ ] 镜像构建没有报错；
- [ ] 容器运行没有中断；
- [ ] 在另外一台设备的浏览器里可以通过 `<树莓派设备 IP>:6789` 访问到网页。

同时，Docker Compose 已经被一起安装，运行 `docker compose version` 查看。

目前是在 root 身份下操作 Docker，如果切换到 iyowei 账户，操作啥都会报如下提示，

```shell
Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Get "http://%2Fvar%2Frun%2Fdocker.sock/v1.24/images/json": dial unix /var/run/docker.sock: connect: permission denied
```

Docker 守护进程绑定到 Unix 套接字而不是 TCP 端口。默认情况下，Unix 套接字属于 root 用户，其他用户只能通过 sudo 访问它。Docker 守护进程始终以 root 用户运行。

如果你不想在 docker 命令前加上 sudo，创建一个名为 docker 的 Unix 组，并向其中添加用户。当 Docker 守护进程启动时，它会创建一个由 Docker 组成员访问的 Unix 套接字。

切换到要操作 Docker 的用户下，查看（`groups`）现有分组里有没有 “docker”。如果现有分组里没有 `docker`，则执行 `sudo groupadd docker` 创建该分组。一般情况下安装 Docker 时默认会创建该分组，执行 `cat /etc/group` 可从全部分组中检查是否存在 `docker` 分组。执行 `sudo usermod -aG docker $USER` 指令将当前用户添加进 “docker” 分组。 重启服务器。执行 `groups iyowei` 检查。

现在每次操作 Docker 时就不需要每次都带上 “sudo” 了。

更多参考，

```shell
To run Docker as a non-privileged user, consider setting up the
Docker daemon in rootless mode for your user:
    dockerd-rootless-setuptool.sh install
Visit https://docs.docker.com/go/rootless/ to learn about rootless mode.
```

## SSH v8.5 ~ v9.8 高危漏洞修复

执行 `bash <(curl -sL kejilion.sh)` 使用 kejilion.sh 脚本操作。

## 虚拟内存

```shell
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
sh -c 'echo "/swapfile none swap sw 0 0" >> /etc/fstab'

systemctl reboot
```

## 系统时区

```shell
timedatectl set-timezone Asia/Shanghai

# 检查时间是否与本地时间一致
date -R

# 输出中包含 "NTP service: active"，则 NTR 服务已开启
timedatectl

systemctl reboot
```

## 网络优化

执行 `wget -N --no-check-certificate "https://get.2sb.org/https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh`，并选择序号 22 号。

重点优化 UDP。

优化后重启。

执行 `sysctl net.ipv4.tcp_congestion_control` 查看当前网络堵塞算法，如果是 "bbr" 说明脚本执行成功。

## 安全组 / 防火墙

```shell
# 自定义 SSH 端口号
ufw allow 59698

ufw allow https
ufw allow http

ufw allow 31820
ufw allow 31821
```

## 防暴力破解

- `apt install fail2ban`，安装 fail2ban；

- `vim /etc/fail2ban/jail.local`，复制当前项目里 "etc/fail2ban/jail.local" 内容；

- `systemctl enable fail2ban`，激活 fail2ban；

- `systemctl start fail2ban`，启用 fail2ban；

- `fail2ban-client status`，查看 fail2ban 运行情况。

## DDoS 防护

内核级 DDoS 防护。`sudo vim /etc/sysctl.conf` 编辑 sysctl 配置，替换为 "etc/sysctl.conf"，及时应用 `sudo sysctl -p`。

安装 `sudo apt install iptables-persistent` iptables 规则自动保存、装载工具。

限制 WireGuard 端口连接频率，
```shell
sudo iptables -A INPUT -p udp --dport 31820 -m hashlimit \
    --hashlimit-above 10/min --hashlimit-burst 5 \
    --hashlimit-mode srcip --hashlimit-name wg_limit \
    -j DROP
```

防止 SYN Flood，
```shell
sudo iptables -A INPUT -p tcp --syn -m hashlimit \
    --hashlimit-above 1/s --hashlimit-burst 3 \
    --hashlimit-mode srcip --hashlimit-name syn_limit \
    -j DROP
```

## 安装 WireGuard

使用 [wg-easy](https://github.com/wg-easy/wg-easy) 进行中心、可视化 WireGuard 管理。

- `docker pull ghcr.io/wg-easy/wg-easy:15`，预先拉取镜像；

- `mkdir -p /etc/docker/containers/wg-easy`，创建存放 wg-easy docker compose 配置文件的地方；

- `cd /etc/docker/containers/wg-easy` 切换到该目录，将 "iyowei/wpn" 项目里的 "etc/docker/containers/wg-easy/docker-compose.yml" 拷贝过来；

- `docker compose up -d --pull always`，启动可视化 WireGuard 管理 Web 服务。