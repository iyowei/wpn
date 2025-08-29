# WireGuard VPN 组网项目 Makefile
# 基于 Ubuntu 24 LTS 系统

.PHONY: help install install-docker install-wireguard install-cron \
	start-wireguard stop-wireguard status logs clean \
	backup restore update test security-setup pack

# 默认目标
help:
	@echo "WireGuard VPN 组网项目管理"
	@echo ""
	@echo "可用命令:"
	@echo "  install            - 完整系统安装 (Docker + WireGuard + 定时任务)"
	@echo "  install-docker     - 仅安装 Docker"
	@echo "  install-wireguard  - 仅安装 WireGuard (wg-easy)"
	@echo "  install-cron       - 仅安装定时任务"
	@echo "  security-setup     - 安装安全配置 (fail2ban + DDoS 防护)"
	@echo ""
	@echo "  start-wireguard    - 启动 WireGuard 服务"
	@echo "  stop-wireguard     - 停止 WireGuard 服务"
	@echo "  restart-wireguard  - 重启 WireGuard 服务"
	@echo "  status             - 查看服务状态"
	@echo "  logs               - 查看服务日志"
	@echo ""
	@echo "  backup             - 备份配置文件"
	@echo "  restore            - 恢复配置文件"
	@echo "  update             - 更新系统和服务"
	@echo "  test               - 运行系统测试"
	@echo "  clean              - 清理临时文件和日志"
	@echo ""
	@echo "  pack               - 打包项目为 zip 文件"
	@echo ""
	@echo "注意: 大部分命令需要 root 权限 (pack 命令除外)"

# 检查 root 权限
check-root:
	@if [ "$$(id -u)" != "0" ]; then \
		echo "错误: 此命令需要 root 权限，请使用 sudo make <command>"; \
		exit 1; \
	fi

# 完整安装
install: check-root
	@echo "开始完整系统安装..."
	$(MAKE) install-docker
	$(MAKE) install-wireguard
	$(MAKE) install-cron
	$(MAKE) security-setup
	@echo "安装完成！"

# 安装 Docker
install-docker: check-root
	@echo "安装 Docker..."
	apt-get update
	apt-get install -y ca-certificates curl gnupg lsb-release
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	echo "deb [arch=$$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $$(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$$VERSION_CODENAME}") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
	apt-get update
	apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	# 配置 Docker 镜像加速
	mkdir -p /etc/docker
	echo '{"registry-mirrors":["https://docker.lixd.xyz/","https://docker.mirrors.ustc.edu.cn","https://docker.nju.edu.cn"]}' > /etc/docker/daemon.json
	systemctl restart docker
	systemctl enable docker
	@echo "Docker 安装完成"

# 安装 WireGuard (wg-easy)
install-wireguard: check-root
	@echo "安装 WireGuard (wg-easy)..."
	docker pull ghcr.io/wg-easy/wg-easy:15
	mkdir -p /etc/docker/containers/wg-easy
	@if [ ! -f /etc/docker/containers/wg-easy/docker-compose.yml ]; then \
		if [ -f etc/docker/containers/wg-easy/docker-compose.yml ]; then \
			cp etc/docker/containers/wg-easy/docker-compose.yml /etc/docker/containers/wg-easy/; \
		else \
			echo "警告: docker-compose.yml 文件未找到，请手动复制"; \
		fi; \
	fi
	@echo "WireGuard 安装完成，请编辑 /etc/docker/containers/wg-easy/docker-compose.yml 后启动服务"

# 安装定时任务
install-cron: check-root
	@echo "安装定时任务..."
	@if [ -f scripts/install-cron.sh ]; then \
		cd scripts && ./install-cron.sh; \
	else \
		echo "错误: scripts/install-cron.sh 未找到"; \
		exit 1; \
	fi
	@echo "定时任务安装完成"

# 安装安全配置
security-setup: check-root
	@echo "安装安全配置..."
	# 安装 fail2ban
	apt-get install -y fail2ban
	@if [ -f etc/fail2ban/jail.local ]; then \
		cp etc/fail2ban/jail.local /etc/fail2ban/jail.local; \
	fi
	systemctl enable fail2ban
	systemctl start fail2ban
	# 应用内核级 DDoS 防护
	@if [ -f etc/sysctl.conf ]; then \
		cp etc/sysctl.conf /etc/sysctl.conf; \
		sysctl -p; \
	fi
	# 安装 iptables 持久化工具
	apt-get install -y iptables-persistent
	@echo "安全配置完成"

# 启动 WireGuard 服务
start-wireguard:
	@echo "启动 WireGuard 服务..."
	cd /etc/docker/containers/wg-easy && docker compose up -d --pull always
	@echo "WireGuard 服务已启动"

# 停止 WireGuard 服务
stop-wireguard:
	@echo "停止 WireGuard 服务..."
	cd /etc/docker/containers/wg-easy && docker compose down
	@echo "WireGuard 服务已停止"

# 重启 WireGuard 服务
restart-wireguard: stop-wireguard start-wireguard

# 查看服务状态
status:
	@echo "=== Docker 服务状态 ==="
	systemctl status docker --no-pager
	@echo ""
	@echo "=== WireGuard 容器状态 ==="
	@if [ -d /etc/docker/containers/wg-easy ]; then \
		cd /etc/docker/containers/wg-easy && docker compose ps; \
	else \
		echo "WireGuard 未安装"; \
	fi
	@echo ""
	@echo "=== 定时任务状态 ==="
	crontab -l 2>/dev/null || echo "无定时任务"
	@echo ""
	@echo "=== 系统负载 ==="
	uptime
	@echo ""
	@echo "=== 内存使用 ==="
	free -h
	@echo ""
	@echo "=== 磁盘使用 ==="
	df -h /

# 查看服务日志
logs:
	@echo "=== WireGuard 服务日志 (最近50行) ==="
	@if [ -d /etc/docker/containers/wg-easy ]; then \
		cd /etc/docker/containers/wg-easy && docker compose logs --tail 50; \
	else \
		echo "WireGuard 未安装"; \
	fi
	@echo ""
	@echo "=== 定时任务日志 ==="
	@if [ -f /var/log/dns-refresh.log ]; then \
		echo "DNS 刷新日志 (最近10行):"; \
		tail -10 /var/log/dns-refresh.log; \
		echo ""; \
	fi
	@if [ -f /var/log/server-reboot.log ]; then \
		echo "服务器重启日志 (最近10行):"; \
		tail -10 /var/log/server-reboot.log; \
		echo ""; \
	fi

# 备份配置文件
backup: check-root
	@echo "备份配置文件..."
	mkdir -p /opt/wpn-backup/$$(date +%Y%m%d-%H%M%S)
	@BACKUP_DIR=/opt/wpn-backup/$$(date +%Y%m%d-%H%M%S); \
	echo "备份目录: $$BACKUP_DIR"; \
	if [ -d /etc/docker/containers/wg-easy ]; then \
		cp -r /etc/docker/containers/wg-easy $$BACKUP_DIR/; \
	fi; \
	if [ -f /etc/fail2ban/jail.local ]; then \
		mkdir -p $$BACKUP_DIR/fail2ban; \
		cp /etc/fail2ban/jail.local $$BACKUP_DIR/fail2ban/; \
	fi; \
	crontab -l > $$BACKUP_DIR/crontab.txt 2>/dev/null || true; \
	cp /etc/sysctl.conf $$BACKUP_DIR/ 2>/dev/null || true; \
	echo "备份完成: $$BACKUP_DIR"

# 恢复配置文件
restore: check-root
	@echo "可用备份:"
	@ls -la /opt/wpn-backup/ 2>/dev/null || echo "无备份文件"
	@echo "请手动选择备份目录进行恢复"

# 更新系统和服务
update: check-root
	@echo "更新系统..."
	apt-get update && apt-get upgrade -y
	@echo "更新 WireGuard 镜像..."
	docker pull ghcr.io/wg-easy/wg-easy:15
	@if [ -d /etc/docker/containers/wg-easy ]; then \
		cd /etc/docker/containers/wg-easy && docker compose up -d --pull always; \
	fi
	@echo "更新完成"

# 运行系统测试
test:
	@echo "运行系统测试..."
	@echo "=== 检查 Docker 状态 ==="
	docker --version
	docker compose version
	systemctl is-active docker
	@echo ""
	@echo "=== 检查 WireGuard 服务 ==="
	@if [ -d /etc/docker/containers/wg-easy ]; then \
		cd /etc/docker/containers/wg-easy && docker compose ps; \
	else \
		echo "WireGuard 未安装"; \
	fi
	@echo ""
	@echo "=== 检查定时任务脚本 ==="
	@if [ -f scripts/test-healthcheck.sh ]; then \
		cd scripts && ./test-healthcheck.sh; \
	else \
		echo "测试脚本未找到"; \
	fi
	@echo ""
	@echo "=== 检查防火墙状态 ==="
	ufw status 2>/dev/null || echo "ufw 未安装或未启用"
	@echo ""
	@echo "=== 检查 fail2ban 状态 ==="
	fail2ban-client status 2>/dev/null || echo "fail2ban 未安装或未启用"

# 清理临时文件和日志
clean: check-root
	@echo "清理临时文件和日志..."
	docker system prune -f
	# 清理旧日志文件 (保留最近7天)
	find /var/log -name "*-*.log" -type f -mtime +7 -delete 2>/dev/null || true
	# 清理 apt 缓存
	apt-get autoremove -y
	apt-get autoclean
	@echo "清理完成"

# 打包项目
pack:
	@echo "打包项目为 zip 文件..."
	@PROJECT_NAME="wpn-$$(date +%Y%m%d-%H%M%S)"; \
	ZIP_FILE="$$PROJECT_NAME.zip"; \
	echo "创建压缩包: $$ZIP_FILE"; \
	zip -r "$$ZIP_FILE" \
		README.md \
		CLAUDE.md \
		SERVER.md \
		PEER.md \
		Makefile \
		scripts/ \
		etc/ \
		-x "*.git*" "*.DS_Store" "*.log" "*~" "*.tmp" \
		2>/dev/null || { \
			echo "错误: zip 命令未找到，请安装 zip 工具"; \
			echo "Ubuntu/Debian: sudo apt install zip"; \
			echo "macOS: brew install zip"; \
			exit 1; \
		}; \
	echo "打包完成: $$ZIP_FILE"; \
	ls -lh "$$ZIP_FILE"
