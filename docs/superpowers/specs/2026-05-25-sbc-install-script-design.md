# SBC 宿主机一键安装脚本 — 设计稿

- 日期:2026-05-25
- 作者:lilong
- 状态:已审批,待写实施计划

## 1. 背景与目标

在一台 Ubuntu 宿主机上,通过一个 shell 脚本一键安装并随开机启动:

- **kamailio 5.8**(来自 `deb.kamailio.org` 仓库)
- **rtpengine 12.5.1**(来自 sipwise `mr12.5.1` 仓库,启用 in-kernel 模式)

参考实现位于 `~/data/project/mygithub/aicallcenter-deploy/{kamailio,rtpengine}/`,当前是 Docker(host 网络)部署。本脚本把同等组件迁到宿主机原生部署,以便启用 rtpengine 内核模块、降低媒体转发延迟与 CPU 占用。

非目标:

- MySQL 与 Redis 由本脚本管理(它们部署在异机)
- 跨发行版兼容(只支持 Ubuntu 系)

## 2. 仓库布局

所有产物统一放在仓库根目录 `install/` 下:

```
sbc/
└── install/
    ├── install.sh                                       # 主入口,含必填变量区
    ├── conf/
    │   ├── kamailio.cfg.tpl                             # 占位符化的模板
    │   ├── kamailio.lua                                 # 原样拷贝(业务逻辑,不参数化)
    │   ├── dispatcher.list                              # 原样拷贝(默认两条对端)
    │   └── rtpengine.conf.tpl                           # 占位符化的模板
    └── systemd/
        ├── kamailio.service.d/override.conf
        └── rtpengine-daemon.service.d/override.conf
```

## 3. 调用约定

```bash
sudo ./install/install.sh install       # 默认:全量安装
sudo ./install/install.sh reconfigure   # 不动包,只重新渲染配置 + 重启服务
```

未传子命令时等同 `install`。

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

# ===== 可选 =====
KAMAILIO_BRANCH="58"                # deb.kamailio.org 分支(5.8)
RTPENGINE_RELEASE="mr12.5.1"
```

## 5. 错误处理与运行模式

- 脚本头部 `set -euo pipefail`
- `trap 'echo "[FAIL] line $LINENO" >&2' ERR`
- 任意一步失败立即停,打印失败行号

## 6. install 模式步骤

按顺序执行,任一步骤失败即终止:

### 6.1 前置检查

- 必须 root(`[ "$EUID" -eq 0 ]`)
- OS 校验:读 `/etc/os-release`,必须 `ID=ubuntu`(版本不限);非 Ubuntu 报错退出
- 读 `VERSION_CODENAME`(jammy / noble / focal ...),用于后续拼接 apt 源
- 必填变量非空校验:`PUBLIC_IP / PRIVATE_IP / LISTEN_IFACE / DB_HOST / DB_USER / DB_PASS / DB_NAME / REDIS_HOST`(REDIS_PASS 允许空,取决于实际部署);任一缺失就报错列出
- 校验 `LISTEN_IFACE` 存在(`ip -o link`),且 `PRIVATE_IP` 绑在该网卡上

### 6.2 apt 基础准备

- `apt-get update`
- 装基础工具:`gnupg ca-certificates curl wget lsb-release dkms linux-headers-$(uname -r)`
- `install -d -m 0755 /etc/apt/keyrings`

### 6.3 添加 kamailio 源

用 `signed-by` 替代已弃用的 `apt-key`:

- `wget -O /etc/apt/keyrings/kamailio.gpg http://deb.kamailio.org/kamailiodebkey.gpg`
- 必要时 `gpg --dearmor` 转 binary
- 写 `/etc/apt/sources.list.d/kamailio.list`:
  `deb [signed-by=/etc/apt/keyrings/kamailio.gpg] http://deb.kamailio.org/kamailio${KAMAILIO_BRANCH} ${VERSION_CODENAME} main`

### 6.4 添加 sipwise 源

- `wget -O /etc/apt/keyrings/sipwise.gpg https://deb.sipwise.com/spce/keyring/sipwise-keyring-bootstrap.gpg`
- 必要时 dearmor
- 写 `/etc/apt/sources.list.d/sipwise.list`:
  `deb [signed-by=/etc/apt/keyrings/sipwise.gpg] https://deb.sipwise.com/spce/${RTPENGINE_RELEASE}/ ${VERSION_CODENAME} main`
- `apt-get update`
- 用 `apt-cache madison ngcp-rtpengine` 探测;若该 codename 下没有任何可用版本,**报错退出**,提示用户调整 `RTPENGINE_RELEASE` 或 OS 版本

### 6.5 安装包

- kamailio + 子模块:

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

- rtpengine:

  ```
  ngcp-rtpengine
  ngcp-rtpengine-kernel-dkms
  ```

### 6.6 加载 rtpengine 内核模块

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

**Debian/Ubuntu 包默认 disable 的坑:**
`sed -i 's/^RUN_KAMAILIO=.*/RUN_KAMAILIO=yes/' /etc/default/kamailio`

### 6.8 装 systemd drop-in

- 拷贝 `install/systemd/kamailio.service.d/override.conf` → `/etc/systemd/system/kamailio.service.d/override.conf`
- 拷贝 `install/systemd/rtpengine-daemon.service.d/override.conf` → `/etc/systemd/system/rtpengine-daemon.service.d/override.conf`
- `systemctl daemon-reload`

### 6.9 启用并启动

- `systemctl enable --now rtpengine-daemon`
- `systemctl enable --now kamailio`
- 各等 3 秒,检查 `systemctl is-active`;任一为 inactive 则 `journalctl -u <unit> -n 50` 输出后非零退出

### 6.10 健康摘要

打印:

- kamailio 版本(`kamailio -v` 第一行)
- rtpengine 版本(`rtpengine --version`)
- 监听端口(`ss -lnup | grep -E "${SIP_UDP_PORT}|${RTPE_NG_PORT}"` 与 `ss -lntp | grep ${SIP_TCP_PORT}`)
- 内核模块状态(`lsmod | grep xt_RTPENGINE`)
- 两个 systemd unit 的 `is-active` / `is-enabled`

## 7. reconfigure 模式步骤

跳过 6.2–6.6,只执行:

1. 6.1 前置检查(变量、网卡)
2. 6.7 渲染配置
3. 6.8 daemon-reload(drop-in 也重新拷贝,允许同时改 unit)
4. `systemctl restart rtpengine-daemon kamailio`
5. 6.10 健康摘要

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
Requires=rtpengine-daemon.service

[Service]
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitNPROC=65535
LimitCORE=infinity
```

- `Requires` + `After` 保证启动顺序与生命周期联动
- 不加 `After=mysql/redis`:DB 与 Redis 异机,本机无对应 unit;kamailio db_mysql 自带重连逻辑

## 9. 开机引导链路

```
boot
 └─ systemd-modules-load.service           # 加载 xt_RTPENGINE
     └─ network-online.target              # 网络就绪
         └─ rtpengine-daemon.service       # enable 后开机自启
             └─ kamailio.service           # Requires + After
```

## 10. 不做的事(显式排除)

- 不管理防火墙(UFW / iptables)
- 不提供 uninstall 子命令
- 不安装 MySQL / Redis(异机)
- 不处理 kamailio 数据库 schema(由现有 DB 提供)
- 不容错降级(严格失败 + 退出)
- 不交互式询问参数(全部走脚本头部变量)

## 11. 可能的失败点与对策

| 失败点 | 对策 |
|---|---|
| sipwise 仓库该 codename 无 `mr12.5.1` | 报错退出,提示调整 `RTPENGINE_RELEASE` |
| linux-headers 与运行内核不匹配 | 6.2 步装的就是 `linux-headers-$(uname -r)`;若内核是定制版无对应 headers,DKMS 编译会失败,脚本以非零退出 |
| `RUN_KAMAILIO=no` 默认 | 6.7 显式改为 yes |
| `PRIVATE_IP` 未绑在 `LISTEN_IFACE` | 6.1 前置检查直接挡掉 |
| MySQL / Redis 不可达 | kamailio 启动可能成功(连接懒加载或重连),也可能失败;脚本只看 systemd is-active,真正的连通性由你自行验证 |

## 12. 验收标准

执行 `sudo ./install/install.sh install` 后:

1. `systemctl is-active kamailio` 与 `systemctl is-active rtpengine-daemon` 均为 `active`
2. `systemctl is-enabled` 均为 `enabled`
3. `lsmod | grep xt_RTPENGINE` 有输出
4. `ss -lnup` 看到 `SIP_UDP_PORT` 和 `RTPE_NG_PORT`(127.0.0.1)在监听
5. 重启宿主机后,以上 4 条仍然成立
6. 在 `/etc/kamailio/kamailio.cfg` / `/etc/rtpengine/rtpengine.conf` 中无 `__XXX__` 残留占位符
