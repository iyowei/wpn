# 任务: 将本机 (Windows) 接入现有 WireGuard 网络

> 用法: 把本文件全文复制给 AI 执行体, 将 `<配置文件内容>` 替换为 wg-easy 生成的客户端配置。每个检查点必须通过, 失败即停。全程需要管理员权限的步骤已在文中标注。

你在一台 Windows 10 或 Windows 11 上执行装配。目标是让本机接入 10.8.0.0/24 虚拟内网, 并通过全部检查点。失败时停止并报告, 不要自行重启计算机。

## 输入

客户端配置 (完整内容):

```ini
<配置文件内容>
```

已知网络信息:
- 网关 rwpn: 10.8.0.1, 公网 Endpoint 139.196.99.84:31820/udp
- 树莓派 rrpi: 10.8.0.3

## 执行步骤

### 1. 权限与网络预检

```powershell
# 必须是以管理员身份运行的 PowerShell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Error "需要管理员权限, 请以管理员身份重新打开 PowerShell"; exit 1 }

$PSVersionTable.PSVersion
Get-NetAdapter | Select-Object Name, Status
```

确认: 系统为 Windows 10 (1809+) 或 Windows 11, 当前进程有管理员权限。

**PowerShell 版本**: 系统自带的 Windows PowerShell 5.1 即可, 不需要额外安装 PowerShell 7。本文所有命令在两个版本上行为一致。唯一需要留意的是写配置文件时显式指定 `-Encoding ASCII` (见第 3 步), 因为两个版本的默认编码不同, 而 WireGuard 的 `.conf` 必须是纯 ASCII。

**检测既有代理客户端**: 这台机器可能已经装了 xray、v2rayN、Nekoray、Clash 一类的代理工具。它们如果用 TUN 模式接管全局流量, 会与 WireGuard 的 `10.8.0.0/24` 路由产生优先级冲突。

```powershell
Get-Process | Where-Object { $_.ProcessName -match 'xray|v2ray|nekoray|clash|sing-box' } | Select-Object ProcessName, Id
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceAlias
```

如果检测到代理进程, 先停止它们再执行装配, 装配完成并验证通过后再决定是否恢复。如果检测到 TUN 类虚拟网卡占用了默认路由, 在报告里注明, 不要自行改路由表。

### 2. 安装 WireGuard

优先用 winget; 没有 winget 时回退到官方安装包。

```powershell
$wgExe = "C:\Program Files\WireGuard\wireguard.exe"

if (Test-Path $wgExe) {
    Write-Host "WireGuard 已安装, 跳过"
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "使用 winget 安装"
    winget install -e --id WireGuard.WireGuard --silent --accept-package-agreements --accept-source-agreements
} else {
    Write-Host "winget 不可用, 下载官方安装包"
    $installer = "$env:TEMP\wireguard-installer.exe"
    Invoke-WebRequest -Uri "https://download.wireguard.com/windows-client/wireguard-installer.exe" -OutFile $installer
    Start-Process -FilePath $installer -ArgumentList "/S" -Wait
}

# 安装后确认
Start-Sleep -Seconds 3
if (-not (Test-Path $wgExe)) { Write-Error "WireGuard 安装失败, 请手动运行安装包后重试"; exit 1 }
Write-Host "WireGuard 已就绪: $wgExe"
```

`winget` 是 Windows 10 1809+ 自带的 App Installer。如果这一步失败且没有 winget, 说明系统缺少 App Installer, 让用户手动安装后再继续, 不要自行修改系统组件。

### 3. 写入配置

```powershell
$tunnelName = "wg0"
$confDir = "C:\ProgramData\WireGuard\Configurations"
New-Item -ItemType Directory -Path $confDir -Force | Out-Null
$confPath = Join-Path $confDir "$tunnelName.conf"

@'
<配置文件内容>
'@ | Set-Content -Path $confPath -Encoding ASCII

# 校验关键字段
Get-Content $confPath | Select-String -Pattern '^(Address|Endpoint|AllowedIPs)'
```

确认输出里 `AllowedIPs = 10.8.0.0/24`。如果包含 `0.0.0.0/0` 立即停止并报告配置错误。

### 4. 安装隧道服务

`/installtunnelservice` 会把配置加密后注册成 Windows 服务, 开机自启, 不需要客户端界面常驻。

```powershell
# 如果已存在同名隧道, 先卸载 (幂等)
$serviceName = "WireGuardTunnel`$$tunnelName"
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    & $wgExe /uninstalltunnelservice $tunnelName
    Start-Sleep -Seconds 2
}

& $wgExe /installtunnelservice $confPath
Start-Sleep -Seconds 3
```

安装成功后服务的显示名是 `WireGuardTunnel$wg0`, 启动类型为自动。

## 检查点 (全部通过才算成功)

| # | 检查项 | 命令 | 通过标准 |
|---|---|---|---|
| 1 | WireGuard 已安装 | `Test-Path "C:\Program Files\WireGuard\wireguard.exe"` | True |
| 2 | 服务已注册 | `Get-Service -Name "WireGuardTunnel$wg0"` | 存在 |
| 3 | 服务运行中 | `(Get-Service -Name "WireGuardTunnel$wg0").Status` | Running |
| 4 | 开机自启 | `(Get-Service -Name "WireGuardTunnel$wg0").StartType` | Automatic |
| 5 | 握手成功 | `& "C:\Program Files\WireGuard\wg.exe" show wg0` | 有 `latest handshake` 且非空 |
| 6 | 地址已分配 | `Get-NetIPAddress -InterfaceAlias "wg0" -ErrorAction SilentlyContinue` | 有 10.8.0.x |
| 7 | 网关可达 | `Test-Connection -ComputerName 10.8.0.1 -Count 3 -Quiet` | True |
| 8 | 树莓派可达 | `Test-Connection -ComputerName 10.8.0.3 -Count 3 -Quiet` | True |

## 失败处理

任何检查点失败时, 输出:

1. 失败的是第几项
2. 相关命令的完整输出
3. 初步判断 (安装失败 / 服务未起 / 无握手 / 握手成功但 ping 不通)
4. 建议的下一步, 不要自行修改配置或重启计算机

常见分支:

- **服务注册失败, 提示 Access is denied**: 当前 PowerShell 不是管理员权限
- **服务存在但启动失败**: 执行 `& $wgExe /uninstalltunnelservice wg0` 卸载后重新安装; 若仍失败, 查看事件查看器 `Windows Logs > System` 里 `WireGuardTunnel$wg0` 的错误
- **无握手**: 出站 UDP 到 139.196.99.84:31820 被防火墙或安全软件拦截, 或 Endpoint 配置错误
- **有握手但 ping 10.8.0.1 不通**: 服务端 AllowedIPs 未包含本机 IP
- **ping 10.8.0.1 通但 10.8.0.3 不通**: rrpi 的 UFW 未放行, 或 rrpi 未在线
- **端口绑定失败 0xc0000022**: 常见于 Hyper-V 预留端口冲突, 换一个客户端 `ListenPort` 重试

## 安全收尾

Windows 防火墙默认阻止入站, 客户端角色不需要额外开放端口。如果本机需要为内网提供其他服务, 逐条添加规则并限定来源:

```powershell
New-NetFirewallRule -DisplayName "WG-Internal-8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -RemoteAddress 10.8.0.0/24 -Action Allow
```

不要用 `-RemoteAddress Any` 放到公网。

## 可选: 后续开发环境管理

WireGuard 装配本身不需要任何语言运行时。如果这台机器之后要跑开发环境, 用 [mise](https://github.com/jdx/mise) 统一管理 Node、Python、Go 等工具的版本, 比逐个装版本管理器省心。它原生支持 Windows, 不需要 WSL。

```powershell
winget install -e --id jdx.mise

# 把激活命令写进 PowerShell 配置, 新开窗口自动生效
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
Add-Content $PROFILE 'mise activate pwsh | Out-String | Invoke-Expression'

# 重开 PowerShell 后验证
mise --version
```

安装语言运行时示例:

```powershell
mise use -g node@22
mise use -g python@3.12
node -v
python --version
```

这一步与 WireGuard 接入完全独立, 跳过不影响装配结果。

## 输出格式

```text
装配结果: 成功 / 失败
检查点: 8/8 通过
隧道服务: WireGuardTunnel$wg0 (Running, Automatic)
接口地址: 10.8.0.x
握手时间: <相对时间>
网关延迟: <ms>
树莓派延迟: <ms>
备注: <任何异常>
```
