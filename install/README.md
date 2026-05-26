# SBC 宿主机一键安装

支持 **kamailio 5.8 / rtpengine 12.5.1 (in-kernel) / caddy**，Ubuntu（任意版本）。

## 用法

```bash
cp install/install.env.example install/install.env
# 编辑 install.env 填好变量

set -a; source install/install.env; set +a
sudo -E ./install/install.sh install
# 弹出 whiptail 多选菜单，空格勾选，回车确认
```

只装某个服务：

```bash
sudo -E ./install/install.sh install caddy
sudo -E ./install/install.sh install kamailio rtpengine
```

重渲配置（不动包）：

```bash
sudo -E ./install/install.sh reconfigure kamailio
```

## 各服务必填变量

| 变量 | kamailio | rtpengine | caddy |
|------|:-:|:-:|:-:|
| PUBLIC_IP / PRIVATE_IP | ✓ | ✓ | |
| LISTEN_IFACE | ✓ | | |
| SIP_*_PORT / KAM_ALIAS_* | ✓ | | |
| DB_* / REDIS_* | ✓ | | |
| RTPE_NG_PORT | ✓ | ✓ | |
| RTPE_PORT_MIN/MAX | | ✓ | |
| CADDY_*_DOMAIN / CADDY_*_UPSTREAM | | | ✓ |

只装某个服务时，无关变量留空即可。

## 验收（每次安装后跑一遍）

```bash
sudo systemctl is-active kamailio rtpengine-daemon caddy
sudo systemctl is-enabled kamailio rtpengine-daemon caddy
sudo lsmod | grep xt_RTPENGINE
sudo ss -lnup | grep -E ':15060|:2223'
sudo ss -lntp | grep -E ':80|:443|:15062'
```

重启宿主机后再跑一遍，所有服务应自动起来。
