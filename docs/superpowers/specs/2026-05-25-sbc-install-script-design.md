# SBC 宿主机一键安装脚本 — 设计稿

- 日期:2026-05-25
- 作者:lilong
- 状态:已审批,待写实施计划

## 1. 背景与目标

在一台 Ubuntu 宿主机上,通过一个 shell 脚本一键安装并随开机启动:

- **kamailio 5.8**(来自 `deb.kamailio.org` 仓库)
- **rtpengine 12.5.1**(来自 sipwise `mr12.5.1` 仓库,启用 in-kernel 模式)
- **caddy**(来自 Cloudsmith `caddy/stable` 仓库,反向代理 + 自动 TLS)

参考实现位于 `~/data/project/mygithub/aicallcenter-deploy/{kamailio,rtpengine,caddy}/`,前两者当前是 Docker(host 网络)部署,caddy 已是宿主机安装脚本。本脚本把同等组件迁到宿主机原生部署,以便启用 rtpengine 内核模块、降低媒体转发延迟与 CPU 占用,并把三个服务的安装入口统一。

非目标:

- MySQL 与 Redis 由本脚本管理(它们部署在异机)
- 跨发行版兼容(只支持 Ubuntu 系)

## 2. 仓库布局

按"服务"分模块化,主入口只负责解析参数和分派,未来新增服务(如 freeswitch)只需加一个 `services/<name>.sh` + 对应的 `conf/<name>/` 和 `systemd/`,主入口零改动:

```
sbc/
└── install/
    ├── install.sh                                       # 主入口:解析参数,dispatch
    ├── lib/
    │   └── common.sh                                    # 共享:OS 校验、apt key、变量校验、健康检查
    ├── services/
    │   ├── kamailio.sh                                  # do_install / do_reconfigure / do_health
    │   ├── rtpengine.sh
    │   └── caddy.sh
    ├── conf/
    │   ├── kamailio/
    │   │   ├── kamailio.cfg.tpl                         # 占位符化的模板
    │   │   ├── kamailio.lua                             # 原样拷贝(业务逻辑)
    │   │   └── dispatcher.list                          # 原样拷贝(默认两条对端)
    │   ├── rtpengine/
    │   │   └── rtpengine.conf.tpl                       # 占位符化的模板
    │   └── caddy/
    │       └── Caddyfile.tpl                            # 占位符化的模板
    └── systemd/
        ├── kamailio.service.d/override.conf
        ├── rtpengine-daemon.service.d/override.conf
        └── caddy.service.d/override.conf
```

每个 `services/<name>.sh` 暴露固定接口供主入口调用:

- `do_install` — 执行该服务的完整 install 步骤
- `do_reconfigure` — 仅重渲配置 + 重启
- `do_health` — 健康摘要

## 3. 调用约定

服务名以**位置参数**列在子命令后面。**不做服务间依赖校验**(传什么操作什么)。

```bash
# 显式列服务:按列表精确操作
sudo ./install/install.sh install kamailio rtpengine    # 装两个
sudo ./install/install.sh install rtpengine             # 只装 rtpengine
sudo ./install/install.sh reconfigure caddy             # 只重渲 caddy

# 不带服务名:弹出 whiptail 多选菜单让用户勾选
sudo ./install/install.sh install
sudo ./install/install.sh reconfigure

# 不传子命令时报错,而非默认 install(避免误操作)
```

**菜单交互细节(无文本输入):**

- 主入口检测到没有传服务名时,调用 `whiptail --checklist`(Ubuntu `whiptail` 包默认存在,脚本前置检查会确保它装上)
- 菜单选项由 `services/` 下的脚本动态生成,默认全部勾选
- 用户用方向键 + 空格切换勾选,Tab 切到 OK,回车确认;Cancel 或勾零项 = 退出码 1
- 非交互终端(`! -t 0`,如 CI 管道)且未传服务名时**报错退出**,不阻塞自动化:这种场景必须显式列服务名

未知服务名报错列出已知服务名后退出。已知服务名由 `services/` 目录里的文件名决定(目前:`kamailio rtpengine caddy`)。

## 4. 必填变量(脚本头部)

```bash
# ===== 必填:网络 =====
PUBLIC_IP=""
PRIVATE_IP=""
LISTEN_IFACE="eth0"

# ===== 必填:kamailio SIP 监听 =====
SIP_UDP_PORT="15060"
SIP_TCP_PORT="15062"
KAM_ALIAS_1="soft.voicelen.cn"
KAM_ALIAS_2="webrtc.voicelen.cn"

# ===== 必填:MySQL(异机) =====
DB_HOST=""
DB_PORT="3306"
DB_USER=""
DB_PASS=""
DB_NAME=""

# ===== 必填:Redis(异机) =====
REDIS_HOST=""
REDIS_PORT="6379"
REDIS_PASS=""

# ===== 必填:rtpengine =====
RTPE_NG_PORT="2223"
RTPE_PORT_MIN="40000"
RTPE_PORT_MAX="60000"

# ===== 必填:caddy 反代 =====
CADDY_API_DOMAIN="api.voicelen.cn"
CADDY_API_UPSTREAM="localhost:18080"
CADDY_APP_DOMAIN="app.voicelen.cn"
CADDY_APP_UPSTREAM="localhost:13000"
CADDY_WEBRTC_DOMAIN="webrtc.voicelen.cn"
CADDY_WEBRTC_UPSTREAM="127.0.0.1:15062"   # 指向 kamailio 的 TCP/WS 端口

# ===== 可选 =====
KAMAILIO_BRANCH="58"                # deb.kamailio.org 分支(5.8)
RTPENGINE_RELEASE="mr12.5.1"
```

**变量与服务的对应关系**(只装某个服务时,无关变量可留空):

- kamailio 用:`PUBLIC_IP / PRIVATE_IP / LISTEN_IFACE / SIP_* / KAM_ALIAS_* / DB_* / REDIS_* / RTPE_NG_PORT / KAMAILIO_BRANCH`
- rtpengine 用:`PUBLIC_IP / PRIVATE_IP / RTPE_NG_PORT / RTPE_PORT_MIN / RTPE_PORT_MAX / RTPENGINE_RELEASE`
- caddy 用:`CADDY_*`

每个服务模块的 `do_install` / `do_reconfigure` 只校验自己用到的变量,装 caddy 时不需要填 DB 信息。

## 5. 错误处理与运行模式

- 脚本头部 `set -euo pipefail`
- `trap 'echo "[FAIL] line $LINENO" >&2' ERR`
- 任意一步失败立即停,打印失败行号

## 6. install 模式步骤

主入口先做全局前置(6.1),再对参数中列出(或默认全部)的每个服务依次调用 `services/<name>.sh::do_install`。下面列的步骤即一个服务模块内部的执行顺序。

按顺序执行,任一步骤失败即终止:

### 6.1 前置检查(全局,由主入口执行一次)

- 必须 root(`[ "$EUID" -eq 0 ]`)
- OS 校验:读 `/etc/os-release`,必须 `ID=ubuntu`(版本不限);非 Ubuntu 报错退出
- 读 `VERSION_CODENAME`(jammy / noble / focal ...),用于后续拼接 apt 源
- 确保 `whiptail` 已安装(交互菜单需要),若无则 `apt-get install -y whiptail`
- 服务级变量校验由各服务模块的 `do_install` 自己负责(只校验自己用到的);kamailio 还会额外校验 `LISTEN_IFACE` 存在且 `PRIVATE_IP` 绑在该网卡上

### 6.2 apt 基础准备(全局)

- `apt-get update`
- 装基础工具:`gnupg ca-certificates curl wget lsb-release whiptail`
- 仅当本次操作包含 rtpengine:追加 `dkms linux-headers-$(uname -r)`
- `install -d -m 0755 /etc/apt/keyrings`

### 6.3 添加 kamailio 源

用 `signed-by` 替代已弃用的 `apt-key`:

- `wget -O /etc/apt/keyrings/kamailio.gpg http://deb.kamailio.org/kamailiodebkey.gpg`
- 必要时 `gpg --dearmor` 转 binary
- 写 `/etc/apt/sources.list.d/kamailio.list`:
  `deb [signed-by=/etc/apt/keyrings/kamailio.gpg] http://deb.kamailio.org/kamailio${KAMAILIO_BRANCH} ${VERSION_CODENAME} main`

### 6.4 添加 sipwise 源(仅 rtpengine 服务模块)

- `wget -O /etc/apt/keyrings/sipwise.gpg https://deb.sipwise.com/spce/keyring/sipwise-keyring-bootstrap.gpg`
- 必要时 dearmor
- 写 `/etc/apt/sources.list.d/sipwise.list`:
  `deb [signed-by=/etc/apt/keyrings/sipwise.gpg] https://deb.sipwise.com/spce/${RTPENGINE_RELEASE}/ ${VERSION_CODENAME} main`
- `apt-get update`
- 用 `apt-cache madison ngcp-rtpengine` 探测;若该 codename 下没有任何可用版本,**报错退出**,提示用户调整 `RTPENGINE_RELEASE` 或 OS 版本

### 6.4b 添加 caddy 源(仅 caddy 服务模块)

- `curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg`
- `chmod 0644 /etc/apt/keyrings/caddy-stable-archive-keyring.gpg`
- `curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list`
- 上游 list 文件已自带 `signed-by` 字段,无需手工改写
- `apt-get update`

### 6.5 安装包(按服务分别执行)

**kamailio 模块:**

```
kamailio
kamailio-mysql-modules
kamailio-redis-modules
kamailio-tls-modules
kamailio-websocket-modules
kamailio-presence-modules
kamailio-json-modules
kamailio-xmpp-modules
kamailio-utils-modules
kamailio-extra-modules
```

覆盖参考 Dockerfile 里 `kamailio-*` 全家桶的核心子集,以及当前 `kamailio.cfg` 中所有 `loadmodule` 用到的模块。

**rtpengine 模块:**

```
ngcp-rtpengine
ngcp-rtpengine-kernel-dkms
```

**caddy 模块:**

```
caddy
```

### 6.6 加载 rtpengine 内核模块(仅 rtpengine 服务模块)

- `modprobe xt_RTPENGINE`
- 写 `/etc/modules-load.d/rtpengine.conf`,内容 `xt_RTPENGINE`,实现开机自动加载
- 验证 `lsmod | grep -q xt_RTPENGINE`,失败即停

### 6.7 渲染配置

模板用 `__KEY__` 风格占位符,脚本用 `sed` 替换。所有写入的配置文件 owner 设为对应服务用户,权限 640(含密码,不能 world-readable)。

**kamailio.cfg 占位符:**

```
__PUBLIC_IP__
__PRIVATE_IP__
__LISTEN_IFACE__
__SIP_UDP_PORT__
__SIP_TCP_PORT__
__KAM_ALIAS_1__
__KAM_ALIAS_2__
__DB_HOST__
__DB_PORT__
__DB_USER__
__DB_PASS__
__DB_NAME__
__REDIS_HOST__
__REDIS_PORT__
__REDIS_PASS__
__RTPE_NG_PORT__
```

写入 `/etc/kamailio/kamailio.cfg`,owner `kamailio:kamailio`,mode 640。

**kamailio.lua / dispatcher.list:** 原样 `install` 到 `/etc/kamailio/`,owner `kamailio:kamailio`,mode 644。

**rtpengine.conf 占位符:**

```
__PRIVATE_IP__
__PUBLIC_IP__
__RTPE_NG_PORT__
__RTPE_PORT_MIN__
__RTPE_PORT_MAX__
```

写入 `/etc/rtpengine/rtpengine.conf`,owner `rtpengine:rtpengine`,mode 640。

**Caddyfile 占位符:**

```
__CADDY_API_DOMAIN__
__CADDY_API_UPSTREAM__
__CADDY_APP_DOMAIN__
__CADDY_APP_UPSTREAM__
__CADDY_WEBRTC_DOMAIN__
__CADDY_WEBRTC_UPSTREAM__
```

写入 `/etc/caddy/Caddyfile`,owner `caddy:caddy`,mode 644(Caddyfile 不含密钥)。渲染后:

- `caddy fmt --overwrite /etc/caddy/Caddyfile`
- `caddy validate --config /etc/caddy/Caddyfile`,失败即停

**Debian/Ubuntu 包默认 disable 的坑:**
`sed -i 's/^RUN_KAMAILIO=.*/RUN_KAMAILIO=yes/' /etc/default/kamailio`

### 6.8 装 systemd drop-in(各服务模块只拷自己的)

- kamailio:`install/systemd/kamailio.service.d/override.conf` → `/etc/systemd/system/kamailio.service.d/override.conf`
- rtpengine:`install/systemd/rtpengine-daemon.service.d/override.conf` → `/etc/systemd/system/rtpengine-daemon.service.d/override.conf`
- caddy:`install/systemd/caddy.service.d/override.conf` → `/etc/systemd/system/caddy.service.d/override.conf`
- `systemctl daemon-reload`

### 6.9 启用并启动(各服务模块只管自己的 unit)

- kamailio:`systemctl enable --now kamailio`
- rtpengine:`systemctl enable --now rtpengine-daemon`
- caddy:`systemctl enable --now caddy`
- 各等 3 秒,检查 `systemctl is-active`;若为 inactive 则 `journalctl -u <unit> -n 50` 输出后非零退出

### 6.10 健康摘要(各服务模块只打自己的)

- kamailio:版本(`kamailio -v` 第一行)、SIP 端口监听(`ss -lnup | grep ${SIP_UDP_PORT}` 与 `ss -lntp | grep ${SIP_TCP_PORT}`)、`is-active` / `is-enabled`
- rtpengine:版本(`rtpengine --version`)、ng 端口监听(`ss -lnup | grep ${RTPE_NG_PORT}`)、内核模块(`lsmod | grep xt_RTPENGINE`)、`is-active` / `is-enabled`
- caddy:版本(`caddy version`)、HTTPS/HTTP 端口(`ss -lntp | grep -E ':80|:443'`)、`is-active` / `is-enabled`

## 7. reconfigure 模式步骤

主入口对参数中列出(或默认全部)的每个服务依次调用 `services/<name>.sh::do_reconfigure`。每个服务模块内部:

1. 6.1 前置检查(变量、网卡)
2. 6.7 渲染该服务的配置
3. 6.8 重拷该服务的 drop-in + `systemctl daemon-reload`
4. `systemctl restart <该服务的 unit>`
5. 6.10 该服务的健康摘要

注:reconfigure 只重启被列出的服务;若同时改了多个服务且有相互依赖,你需自行控制顺序(如先 `reconfigure rtpengine` 再 `reconfigure kamailio`)。

## 8. systemd drop-in 内容

### 8.1 rtpengine-daemon

```ini
[Unit]
After=network-online.target
Wants=network-online.target
ConditionPathExists=/sys/module/xt_RTPENGINE

[Service]
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitNPROC=65535
LimitCORE=infinity
```

`ConditionPathExists` 防止内核模块未加载时服务静默以 userspace 启动。模块由 `/etc/modules-load.d/rtpengine.conf` 经 `systemd-modules-load.service` 开机加载,该服务排在 `sysinit.target` 之前,远早于 rtpengine。

### 8.2 kamailio

```ini
[Unit]
After=network-online.target rtpengine-daemon.service
Wants=network-online.target
# 不写 Requires=rtpengine-daemon.service:rtpengine 可能装在另一台机器或本机未装
# 让用户自行决定;只用 After 表达顺序,不强制启停联动

[Service]
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitNPROC=65535
LimitCORE=infinity
```

- `After` 保证若本机同时装了 rtpengine,启动顺序正确;但不用 `Requires`,因为按服务可选安装的模式下 rtpengine 不一定本机存在
- 不加 `After=mysql/redis`:DB 与 Redis 异机,本机无对应 unit;kamailio db_mysql 自带重连逻辑

### 8.3 caddy

```ini
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Restart=always
RestartSec=3
LimitNOFILE=65535
```

caddy 自带的 unit 已较完善,drop-in 主要是统一 `Restart` 行为与 ulimit。

## 9. 开机引导链路

```
boot
 └─ systemd-modules-load.service           # 加载 xt_RTPENGINE(仅当装了 rtpengine)
     └─ network-online.target              # 网络就绪
         ├─ rtpengine-daemon.service       # enable 后开机自启
         ├─ kamailio.service               # After=rtpengine-daemon.service(若本机有)
         └─ caddy.service                  # 独立启动
```

## 10. 不做的事(显式排除)

- 不管理防火墙(UFW / iptables)
- 不提供 uninstall 子命令
- 不安装 MySQL / Redis(异机)
- 不处理 kamailio 数据库 schema(由现有 DB 提供)
- 不容错降级(严格失败 + 退出)
- 不交互式询问参数值(变量值仍由脚本头部填写;**交互只用于"选哪些服务"**,通过 whiptail 多选菜单)
- 不做服务间依赖校验(传什么装什么,如只装 kamailio 不装 rtpengine,kamailio 启动后媒体会不可用,由用户自行保证依赖关系)
- 不管理 caddy TLS 证书:caddy 自动 ACME,前提是 80/443 可达且域名 DNS 解析正确

## 11. 可能的失败点与对策

| 失败点 | 对策 |
|---|---|
| sipwise 仓库该 codename 无 `mr12.5.1` | 报错退出,提示调整 `RTPENGINE_RELEASE` |
| linux-headers 与运行内核不匹配 | 6.2 步装的就是 `linux-headers-$(uname -r)`;若内核是定制版无对应 headers,DKMS 编译会失败,脚本以非零退出 |
| `RUN_KAMAILIO=no` 默认 | 6.7 显式改为 yes |
| `PRIVATE_IP` 未绑在 `LISTEN_IFACE` | 6.1 前置检查直接挡掉 |
| MySQL / Redis 不可达 | kamailio 启动可能成功(连接懒加载或重连),也可能失败;脚本只看 systemd is-active,真正的连通性由你自行验证 |

## 12. 验收标准

执行 `sudo ./install/install.sh install`,在弹出的 whiptail 菜单中勾选全部三项,然后:

1. `systemctl is-active kamailio rtpengine-daemon caddy` 三个均为 `active`
2. `systemctl is-enabled` 三个均为 `enabled`
3. `lsmod | grep xt_RTPENGINE` 有输出
4. `ss -lnup` 看到 `SIP_UDP_PORT` 和 `RTPE_NG_PORT` 在监听;`ss -lntp` 看到 caddy 监听 80 / 443
5. 重启宿主机后,以上 4 条仍然成立
6. 在 `/etc/kamailio/kamailio.cfg`、`/etc/rtpengine/rtpengine.conf`、`/etc/caddy/Caddyfile` 中无 `__XXX__` 残留占位符
7. 命令 `sudo ./install/install.sh install caddy` 只装 caddy,不弹菜单,不需要 DB/Redis 等变量
8. 在非交互终端(如 `</dev/null` 重定向)下不带服务名运行,应直接退出非零并报"必须显式列服务名"
