# CLAUDE.md

> 本仓库的 Claude Code 工作指南。每次接手前先读一遍。

## 项目是什么

SBC(Session Border Controller)宿主机一键安装脚本。在 Ubuntu 上原生部署 **kamailio 5.8 + rtpengine 12.5.1 (in-kernel) + caddy**,通过 systemd 管理、随开机启动。Docker 版的参考实现在 `~/data/project/mygithub/aicallcenter-deploy/{kamailio,rtpengine,caddy}/`,但本仓库是宿主机原生部署版本。

## 关键文档(先读)

- **设计稿**:`docs/superpowers/specs/2026-05-25-sbc-install-script-design.md`
- **实施计划**:`docs/superpowers/plans/2026-05-26-sbc-install-script.md`
- **真机验收**:`docs/superpowers/checklists/sbc-install-smoke.md`
- **用户文档**:`install/README.md`

## 目录布局

```
install/
├── install.sh                    # 主入口:参数解析、whiptail 菜单、ensure_prereqs、dispatch
├── install.env.example           # 变量样例(install.env 已 .gitignore)
├── lib/common.sh                 # require_root / detect_ubuntu / require_vars / render_tpl / wait_for_active
├── services/
│   ├── kamailio.sh / rtpengine.sh / caddy.sh   # do_install / do_reconfigure / do_health
│   └── _stub.sh                  # 仅供 bats 测试
├── conf/{kamailio,rtpengine,caddy}/            # 模板(*.tpl)+ 原样文件
└── systemd/                                    # 三个 drop-in

tests/bats/                       # 34 测试(纯函数 + dispatch)
docs/superpowers/{specs,plans,checklists}/
```

## 架构约定(改代码前必读)

### 服务模块同形
每个 `services/<name>.sh` 暴露 **`do_install` / `do_reconfigure` / `do_health`** 三函数;主入口 `install.sh` 在子 shell 中 `source` 后调用对应函数。`KNOWN_SERVICES=(kamailio rtpengine caddy)` 在 `install.sh` 顶部硬编码 —— 加 freeswitch 时:`services/freeswitch.sh` + `conf/freeswitch/` + `systemd/freeswitch.service.d/` + 把名字加进 `KNOWN_SERVICES`,**主入口和 common.sh 零改动**。

### 命名规则
- 私有函数前缀 `_<svc>_xxx`(避免子 shell 中跨模块意外覆盖)
- `_<svc>_install_dir`(**不是** `_<svc>_repo_root`)返回 `install/` 子目录绝对路径
- 必填变量用 `: "${X:=}"` 保护(防 `set -u`),`require_vars` 把空字符串识别为 missing

### render_tpl 设计要点(`install/lib/common.sh`)
- 用 `export` + `ENVIRON[]` 把值传给 awk(**不**用 `awk -v`,后者会做 C 风格转义把 `\foo` 变成换页符)
- 替换用 `index() + substr()` 循环(**不**用 `gsub`,后者的替换串里 `&` 是元字符)
- 渲染后用 `grep -oE '__[A-Z][A-Z0-9_]*__'` 扫残留占位符,有残留即 `return 1`
- 这套写法跨 BSD awk / gawk / mawk 都安全 —— 不要"优化"回 gsub 或 `-v`

### common.sh 顶部不要 `set -o pipefail`
会污染 source 调用方的 shell 状态。错误传播靠各函数自己 `return 1`。

### 测试约定
- bats 通过 `./tests/bats/run.sh` 跑(docker 容器内 bash 5 + mawk)
- 临时目录用 **`TEST_TMPDIR`**,不用 `TMPDIR`(会覆盖系统变量)
- root 校验用 `_EUID_OVERRIDE` 注入(bash 中 `EUID` 是 readonly,直接赋值会失败)
- 测试旁路三件套:`SKIP_ROOT_CHECK=1` / `SKIP_OS_CHECK=1` / `SKIP_PREREQ=1` + `INSTALL_SERVICES_DIR=<stub-dir>`
- bats 只测纯函数(渲染、变量校验、参数解析、dispatch);真包 `apt`/`systemctl`/`modprobe` 由真机 smoke checklist 验

### systemd
- 三个 drop-in 在 `install/systemd/<unit>/override.conf`,加 `Restart=always`、ulimits、特定的 `After=`/`Wants=`
- **不**写 `Requires=rtpengine-daemon.service`(rtpengine 可能不在本机)
- rtpengine drop-in 有 `ConditionPathExists=/sys/module/xt_RTPENGINE` + `After=systemd-modules-load.service`,确保内核模块先就位
- rtpengine **必须** `table = 0`(in-kernel)—— 参考的 docker 版用 `table = -1` 是 userspace,本仓库不要抄

### dispatcher.list 不在仓库
`install/conf/kamailio/dispatcher.list.example` 是模板,首次 `install kamailio` 时**只在 `/etc/kamailio/dispatcher.list` 不存在时**才落一份占位副本并 stderr 警告。运维必须手填真实上游网关 IP 再 `reconfigure`。**不要**把示例 IP commit 进仓库当默认值。

### ensure_prereqs(干净 Ubuntu 不带 wget/curl/whiptail)
`install.sh::main` 在 root/OS 校验后会跑 `ensure_prereqs "$@"`,自动装 `gnupg ca-certificates curl wget whiptail`,如果命令行里有 `rtpengine` 或菜单交互式(空参),追加 `dkms linux-headers-$(uname -r)`。**新加服务**(如 freeswitch)若需要额外系统包,加在 `ensure_prereqs` 的条件分支里。

### apt 源密钥
全部走 `signed-by=/etc/apt/keyrings/<name>.gpg`,**不**用废弃的 `apt-key`。每个 `_<svc>_add_repo` 末尾用 `apt-get update -o Dir::Etc::sourcelist="sources.list.d/<file>.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"` 只刷新自己新加的源(避免多 service 全装时重复 update)。

### health check
**不**用 `sleep N + is-active`,用 `wait_for_active <unit> <timeout>`(在 `common.sh`)。kamailio 用 30s,caddy/rtpengine 15s。

### caddy 渲染是事务性的
先写 `/etc/caddy/Caddyfile.new`,`caddy fmt` + `caddy validate` 通过后再 `install -m 644 -o caddy -g caddy` 原子替换。校验失败时旧 Caddyfile 不动。

## 工作流约定

- **直接在 main 分支工作**(已确认偏好);不用 git worktree
- 提交时永远走 HEREDOC commit message:`git commit -m "$(cat <<'EOF' ... EOF)"`
- 重要改动跑 `./tests/bats/run.sh` 确认 34 tests(33 pass + 1 whiptail skip)
- **不**写 README 之外的 markdown 文档(spec/plan/checklist 已经够);需要时再加

## 不要做的事

- 不要把 `install.env`(真实密钥版)commit 进仓库 —— `.gitignore` 已屏蔽
- 不要在 macOS 上跑 `apt-get`/`systemctl`/`modprobe`/`caddy` 这些命令测试(它们没有)。真机 smoke 才测这些
- 不要修改 `install/conf/kamailio/kamailio.lua`(业务逻辑,原样从参考目录拷贝)
- 不要给服务模块加 `set -e`(install.sh 已 `set -euo pipefail`,子 shell 继承)
- 不要给 install.sh 添加交互式询问"变量值"的 prompt(只有"选哪些服务"是交互的,值靠 install.env)
