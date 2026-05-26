# SBC 安装 — 真机 smoke 验收

每次发布到新环境前在干净的 Ubuntu 机器上跑一遍。

## 前置

- [ ] 准备一台干净 Ubuntu 22.04 或 24.04 机器,SSH 进入
- [ ] 仓库 clone 到 `/root/sbc`
- [ ] 拷贝并填好 `install/install.env`(参考 `install.env.example`)
- [ ] 网卡 / IP 信息核对正确(`ip a` 与 `install.env` 中的 PRIVATE_IP 一致)

## 全装(交互式菜单)

- [ ] `cd /root/sbc && set -a && source install/install.env && set +a`
- [ ] `sudo -E ./install/install.sh install`
- [ ] whiptail 菜单弹出,默认三项均勾选,回车确认
- [ ] 脚本顺序输出 `>>> install: kamailio`、`>>> install: rtpengine`、`>>> install: caddy`(顺序可能不同,但都出现)
- [ ] 退出码 0
- [ ] `systemctl is-active kamailio rtpengine-daemon caddy` 三行全是 `active`
- [ ] `systemctl is-enabled kamailio rtpengine-daemon caddy` 三行全是 `enabled`
- [ ] `lsmod | grep xt_RTPENGINE` 有输出
- [ ] `ss -lnup | grep -E ':15060|:2223'` 看到两个端口
- [ ] `ss -lntp | grep -E ':80|:443|:15062'` 看到 80/443/15062
- [ ] **填 dispatcher.list**:`sudo vi /etc/kamailio/dispatcher.list`,把示例 IP 改成你的真实上游网关,然后 `sudo -E ./install/install.sh reconfigure kamailio`

## 重启验收

- [ ] `sudo reboot`
- [ ] 重启后 SSH 进入
- [ ] 上面"全装"末尾的 5 条检查再次全部通过

## 单服务安装

- [ ] 在另一台干净机器上,只装 caddy:`sudo -E ./install/install.sh install caddy`
- [ ] 不弹菜单,直接装
- [ ] 退出码 0,`systemctl is-active caddy` 为 `active`
- [ ] 没有装 kamailio / rtpengine(`dpkg -l | grep -E 'kamailio|ngcp'` 无输出)

## 非交互式必须显式列服务

- [ ] `sudo -E ./install/install.sh install </dev/null` 应非零退出,提示需要显式列服务名

## reconfigure

- [ ] 改 `install.env` 里某个变量(例如 `CADDY_API_DOMAIN`)
- [ ] `sudo -E ./install/install.sh reconfigure caddy`
- [ ] 退出码 0,`/etc/caddy/Caddyfile` 中能看到新域名
- [ ] caddy 服务仍 `active`

## 失败回归

- [ ] 故意把 `PRIVATE_IP` 改成本机没有的 IP
- [ ] `sudo -E ./install/install.sh reconfigure kamailio`
- [ ] 应非零退出,报错提示 PRIVATE_IP 未绑定在网卡
- [ ] kamailio 服务状态不变(未被重启破坏)
