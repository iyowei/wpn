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
