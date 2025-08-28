# 自动化脚本说明

## 定时任务

### 文件说明

- `dns-refresh.sh` - DNS 刷新脚本，用于清理 DNS 缓存
- `server-reboot.sh` - 服务器重启脚本，记录系统状态后重启服务器
- `install-cron.sh` - 安装脚本，用于设置所有定时任务
- `test-scripts.sh` - 测试脚本，用于验证所有脚本的语法和依赖

### 安装使用

⚠️ **权限要求**：所有脚本都需要 root 权限才能正常执行。

1. 在服务器上执行：
```bash
cd /path/to/wpn/scripts
sudo ./install-cron.sh
```

2. 验证安装：
```bash
# 查看定时任务
crontab -l

# 查看时区设置
timedatectl

# 手动测试 DNS 刷新脚本
sudo ./dns-refresh.sh

# 手动测试服务器重启脚本（注意：会真的重启服务器）
sudo ./server-reboot.sh

# 运行测试脚本验证所有功能
./test-scripts.sh

# 查看日志
tail -f /var/log/dns-refresh.log
tail -f /var/log/server-reboot.log
```

### 定时任务说明

#### DNS 刷新任务
- 执行时间：每天上海时间早上 6:00
- 权限要求：root 权限
- 日志文件：`/var/log/dns-refresh.log`
- Crontab 条目：`0 6 * * * TZ='Asia/Shanghai' /path/to/dns-refresh.sh`

#### 服务器重启任务
- 执行时间：每天上海时间早上 6:05
- 权限要求：root 权限
- 日志文件：`/var/log/server-reboot.log`
- Crontab 条目：`5 6 * * * TZ='Asia/Shanghai' /path/to/server-reboot.sh`

### 脚本功能详情

#### DNS 刷新方法
脚本会尝试以下方法清理 DNS 缓存：
1. `systemd-resolve --flush-caches` (systemd 系统)
2. `/etc/init.d/dns-clean start` (传统 init 系统)
3. 重启 `systemd-resolved` 服务

#### 服务器重启前检查
重启脚本会记录以下系统信息：
1. 系统运行时间（uptime）
2. 内存使用情况
3. 根分区磁盘使用情况
4. 运行中的 Docker 容器状态
5. 同步文件系统缓存到磁盘

所有操作都会记录到对应的日志文件中，方便排查问题。

### 注意事项

#### 权限要求
- 所有脚本在手动执行时都需要 root 权限
- cron 任务需要以 root 用户身份运行（因为脚本内部有权限检查）
- 脚本会自动检查权限，如果没有 root 权限会退出并提示

#### 服务器重启警告
⚠️ **重要警告**：服务器重启任务会在每天早上 6:05 自动重启服务器，请确保：
1. 在此时间段没有重要任务运行
2. 已保存所有重要数据
3. 服务配置为开机自启动
4. 如不需要定期重启，请手动删除相关 crontab 条目

#### 时区设置
- 脚本会自动设置系统时区为 `Asia/Shanghai`
- 如果需要不同时区，请手动调整 crontab 条目或系统时区

#### 系统兼容性
- 支持 Ubuntu/Debian 系统
- 支持 systemd 和传统 init 系统
- 自动检查依赖命令的可用性
- 在缺少某些命令时提供备选方案

#### 错误处理
- 所有脚本都具备完善的错误处理机制
- 在关键操作失败时会自动回滚
- 所有错误和警告都会记录到日志文件
- 安装前会备份现有 crontab 配置