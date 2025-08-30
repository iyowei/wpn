在 Claude Code 对话中使用中文交流。

这个项目专注于沉淀 WireGuard VPN 组网解决方案，基于 Ubuntu 24 LTS 操作系统。

查看 @README.md 了解当前项目。
查看 @SERVER.md 了解初始化一台 WireGuard 服务器细节。
查看 @PEER.md 了解 WireGuard 端节点细节。

## 脚本

Makefile 正确使用 Tab 缩进。

所有 Shell 脚本正确使用 2 个空格缩进。

仅需支持在 Ubuntu 24 LTS 上能够高效运行即可，无需考虑别的系统平台。

脚本中提示语用中文，中文与个别英文术语前后用空格相隔。

定时任务设定的时间都是中国上海时间。

每个脚本预埋充分的日志，并且使用日志轮转机制，每次任务执行前创建格式为 `<任务名称>-<YYYYMMDD-HHMMSS>.log` 的新日志文件用来存储当前任务执行日志。每次任务执行前自动清理超过 7 天的旧日志文件。

终端消息、日志消息等不要有表情。

具备生产环境的高可靠性和安全性。

方糖酱发送消息 Shell 脚本参考，

```shell
#!/bin/bash

# 最新 Shell 示例源码参见 https://gitee.com/easychen/serverchan-demo/blob/master/shell/send.sh

function sc_send() {
    local text=$1
    local desp=$2
    local key=$3

    postdata="text=$text&desp=$desp"
    opts=(
        "--header" "Content-type: application/x-www-form-urlencoded"
        "--data" "$postdata"
    )

    # 判断 key 是否以 "sctp" 开头，选择不同的 URL
    if [[ "$key" =~ ^sctp([0-9]+)t ]]; then
        # 使用正则表达式提取数字部分
        num=${BASH_REMATCH[1]}
        url="https://${num}.push.ft07.com/send/${key}.send"
    else
        url="https://sctapi.ftqq.com/${key}.send"
    fi


    # 使用动态生成的 url 发送请求
    result=$(curl -X POST -s -o /dev/null -w "%{http_code}" "$url" "${opts[@]}")
    echo "$result"
}

# 读取配置文件
data=$(cat "$PWD/../.env")
eval "$data"

# 调用sc_send函数
ret=$(sc_send '主人服务器宕机了 via shell' $'第一行\n\n第二行' "$SENDKEY")
echo "$ret"
```

@scripts/install-cron.sh 脚本每次执行时，要把老的定时任务移除，每次当前脚本设置定时任务，还是要持久存储一下，方便下一次设置最新定时任务时把之前的移除掉。

`crontab -l` 参考格式，
```
# WPN-CRON-TASK: DNS 刷新任务 (每日 06:00)
0 6 * * * TZ='Asia/Shanghai' /root/wpn-20250830-190657/scripts/dns-refresh.sh

# WPN-CRON-TASK: 服务器重启任务 (每日 06:05)
5 6 * * * TZ='Asia/Shanghai' /root/wpn-20250830-190657/scripts/server-reboot.sh

# WPN-CRON-TASK: WireGuard 健康检查任务 (每小时的 9-59 分钟)
9-59 * * * * TZ='Asia/Shanghai' /root/wpn-20250830-190657/scripts/wireguard-healthcheck.sh
```

所有 Shell 脚本均要使用 shellcheck 检查且通过。

# 项目压缩包

测试压缩包前，应先复制到项目外，在项目外进行测试，并及时清理。

压缩包结构，
```
- wpn-20250830-143022.zip
  - Makefile（移除了 pack 指令）
  - scripts/
  - etc/
```

压缩包仅包含上述结构所示文件、文件夹。

## 终端、轮转、推送消息机制

@wpn-zip-handler.sh
@scripts/install-cron.sh
这两份脚本只需要充分、详细的终端日志即可。

定时任务也需要详细的终端日志，尤其是 WireGuard 服务健康检查这样的任务，每一处检查都应该有详细的日志，同时将终端日志同步到日志文件中去。

推送消息，就从最终/最新的日志文件里读取，用 Markdown 文段的方式，一条条转化，显示一行，空一行.
