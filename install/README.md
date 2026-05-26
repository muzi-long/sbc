# SBC 宿主机一键安装

支持 **kamailio 5.8 / rtpengine 12.5.1 (in-kernel) / caddy**，**Debian 12 (bookworm)**。

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

## kamailio dispatcher 配置(重要)

`install/conf/kamailio/dispatcher.list.example` 是模板,**不**包含真实业务网关 IP。
首次 `install kamailio` 后,你必须手动编辑 `/etc/kamailio/dispatcher.list`,填入你的真实上游 FreeSWITCH / PSTN 网关地址,然后:

```bash
sudo -E ./install/install.sh reconfigure kamailio
```

格式参考(每行一条:setid sip:host:port [flags]):
```
1 sip:10.0.0.5:5080
2 sip:1.2.3.4:5060 4
```
- setid=1:本地 FreeSWITCH 软交换集群
- setid=2:上游 PSTN 网关(flags=4 表示需要探活)

如果不改,kamailio 仍然能启动,但 dispatcher 探活无对端,呼叫会 503。

## 各服务必填变量

| 变量 | kamailio | rtpengine | caddy | freeswitch |
|------|:-:|:-:|:-:|:-:|
| PUBLIC_IP / PRIVATE_IP | ✓ | ✓ | | |
| LISTEN_IFACE | ✓ | | | |
| SIP_*_PORT / KAM_ALIAS_* | ✓ | | | |
| DB_* / REDIS_* | ✓ | | | |
| RTPE_NG_PORT | ✓ | ✓ | | |
| RTPE_PORT_MIN/MAX | | ✓ | | |
| CADDY_*_DOMAIN / CADDY_*_UPSTREAM | | | ✓ | |

只装某个服务时，无关变量留空即可。

> **freeswitch 无必填变量**。配置走 `/usr/local/freeswitch/conf/`：首次安装从 `install/conf/freeswitch/conf/` 原样拷入，后续 `reconfigure` 不覆盖运维已改动的文件。

## 验收（每次安装后跑一遍）

```bash
sudo systemctl is-active kamailio ngcp-rtpengine-daemon caddy
sudo systemctl is-enabled kamailio ngcp-rtpengine-daemon caddy
sudo lsmod | grep xt_RTPENGINE
sudo ss -lnup | grep -E ':15060|:2223'
sudo ss -lntp | grep -E ':80|:443|:15062'
```

如果安装了 freeswitch，额外验收：

```bash
sudo systemctl is-active freeswitch
sudo /usr/local/freeswitch/bin/fs_cli -x "status" | head -5
sudo ss -lnup | grep -E ':5060|:5080'
```

重启宿主机后再跑一遍，所有服务应自动起来。
