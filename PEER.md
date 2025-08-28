# 端节点

# 客户端分流规则

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
