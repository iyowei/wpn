# ROADMAP

## 待办

- [ ] **部署免重建 .env**: 打包时带上 `.env.example`, 部署脚本检测 `.env` 不存在才从模板生成, 避免每次更新压缩包都要手工重建
- [ ] **出站带宽限制与验证**: 先在端节点用 `tc` 做出站限速, 再用 `iperf3` 与 `curl` 测实际效果
- [ ] **防火墙脚本实跑核对**: `firewall-rrpi.sh` 是文本搬运, 尚未在 rrpi 上执行过; 实跑一次并核对白名单端口与容器实际监听一致
- [ ] **拆分后的打包流程实测**: 确认压缩包只含 `scripts/` 与 `etc/`, 且 `make install` 能在干净网关上跑通
- [ ] **网关初始化收成一条链路**: server-forge 装主机底座, wpn 装 WireGuard, 中间不出现手工补配置的断点

## 已完成 (2026-10-23 核对)

- [X] Nginx 编译安装、HTTPS 与 HTTP/3 双栈: 通用配置与文档已迁 nginx-forge, rwpn 已同步
- [X] 禁止公网访问 WireGuard Web 管理界面: 31821 绑定 `127.0.0.1`, 无公网 UFW 规则
- [X] 主机层装配拆到 server-forge
- [X] 边缘节点防火墙规则脚本化为 `firewall-rrpi.sh`

## 已移交

- 暴力破解保护效果测试: fail2ban 与 sysctl 规则现在归 server-forge, 该测试随之转移
