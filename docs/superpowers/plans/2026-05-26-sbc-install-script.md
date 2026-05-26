# SBC 宿主机一键安装脚本 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Ubuntu 宿主机上一键安装并随开机启动 kamailio 5.8、rtpengine 12.5.1(in-kernel)、caddy,通过 whiptail 多选菜单或位置参数选择服务,严格失败模式。

**Architecture:** 按服务模块化的 bash 脚本树。主入口 `install.sh` 解析参数 + 弹菜单,各 `services/<name>.sh` 暴露 `do_install`/`do_reconfigure`/`do_health` 接口。配置以 `__KEY__` 占位符模板形式存放,运行时由 `lib/common.sh` 的 `render_tpl` 用 awk 替换。systemd 通过 drop-in 加固。纯函数(变量校验、模板渲染、参数解析)用 bats 做单测,真包安装由人在真机 smoke 验收。

**Tech Stack:** bash 5+、whiptail(newt)、systemd、apt(signed-by 密钥)、bats-core(测试)。

**Spec:** `docs/superpowers/specs/2026-05-25-sbc-install-script-design.md`

**已知服务清单:** `kamailio rtpengine caddy`(顺序敏感:菜单和默认列表按此顺序展示)

---

## Task 1: 仓库脚手架与 bats 测试框架

**Files:**
- Create: `install/install.sh`
- Create: `install/lib/common.sh`
- Create: `.editorconfig`(仓库根目录,适用于整仓库)
- Create: `tests/bats/run.sh`
- Create: `tests/bats/helpers.bash`
- Create: `tests/bats/test_smoke.bats`
- Create: `.gitignore`(追加 bats 临时产物)

**目标:** 把目录骨架搭起来,bats 在容器里跑得通,先有一个"hello world"测试通过。后续每个任务都加 bats 测试。

- [ ] **Step 1: 写 .gitignore**

```gitignore
# 已有内容(若 .gitignore 存在,只追加下面这段)
tests/bats/.bats-tmp/
tests/bats/lib/
```

- [ ] **Step 2: 写 tests/bats/run.sh —— 一键拉起 bats(用 docker,免装本地依赖)**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 用官方 bats docker 镜像,把仓库挂进去
exec docker run --rm \
  -v "${REPO_ROOT}:/code" \
  -w /code \
  bats/bats:1.10.0 \
  tests/bats
```

设可执行:`chmod +x tests/bats/run.sh`

- [ ] **Step 3: 写 tests/bats/helpers.bash —— 公共加载器**

```bash
# tests/bats/helpers.bash
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
export REPO_ROOT
```

- [ ] **Step 4: 写 tests/bats/test_smoke.bats**

```bash
#!/usr/bin/env bats
load 'helpers'

@test "repo root resolves" {
  [ -n "$REPO_ROOT" ]
  [ -d "$REPO_ROOT/install" ] || skip "install dir not yet created"
}

@test "bash version >= 4" {
  run bash --version
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 5: 创建 install/ 骨架占位**

```bash
mkdir -p install/lib install/services install/conf/kamailio install/conf/rtpengine install/conf/caddy install/systemd
touch install/install.sh install/lib/common.sh
chmod +x install/install.sh
```

- [ ] **Step 6: 写 .editorconfig**

```ini
root = true

[*.sh]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true
```

- [ ] **Step 7: 跑测试**

Run: `./tests/bats/run.sh`
Expected:
```
 ✓ repo root resolves
 ✓ bash version >= 4

2 tests, 0 failures
```

- [ ] **Step 8: 提交**

```bash
git add install/ tests/ .gitignore .editorconfig
git commit -m "scaffold install dir + bats test harness"
```

---

## Task 2: lib/common.sh — OS 校验

**Files:**
- Modify: `install/lib/common.sh`
- Create: `tests/bats/test_common_os.bats`

**目标:** 写 `require_root` 和 `detect_ubuntu` 两个函数。`detect_ubuntu` 从 `/etc/os-release` 读出 codename,非 Ubuntu 返回非零。

- [ ] **Step 1: 写 failing test**

```bash
# tests/bats/test_common_os.bats
#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "detect_ubuntu reads codename from os-release file" {
  cat > "$TMPDIR/os-release" <<EOF
ID=ubuntu
VERSION_ID="22.04"
VERSION_CODENAME=jammy
EOF
  run detect_ubuntu "$TMPDIR/os-release"
  [ "$status" -eq 0 ]
  [ "$output" = "jammy" ]
}

@test "detect_ubuntu fails on debian" {
  cat > "$TMPDIR/os-release" <<EOF
ID=debian
VERSION_CODENAME=bookworm
EOF
  run detect_ubuntu "$TMPDIR/os-release"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Ubuntu"* ]]
}

@test "detect_ubuntu fails when codename missing" {
  cat > "$TMPDIR/os-release" <<EOF
ID=ubuntu
EOF
  run detect_ubuntu "$TMPDIR/os-release"
  [ "$status" -ne 0 ]
}

@test "require_root passes when EUID=0" {
  # bash 中 EUID 是 readonly,用 _EUID_OVERRIDE 测试注入点
  _EUID_OVERRIDE=0 run require_root
  [ "$status" -eq 0 ]
}

@test "require_root fails when EUID!=0" {
  _EUID_OVERRIDE=1000 run require_root
  [ "$status" -ne 0 ]
  [[ "$output" == *"root"* ]]
}
```

- [ ] **Step 2: 跑测试,确认 fail**

Run: `./tests/bats/run.sh`
Expected: `detect_ubuntu: command not found` 类失败

- [ ] **Step 3: 实现 install/lib/common.sh**

```bash
#!/usr/bin/env bash
# install/lib/common.sh
# 共享工具函数。所有 shell 函数都用 `(... )` 子 shell 形式以隔离副作用,
# 或在文档中显式说明会修改的全局变量。

set -o pipefail

require_root() {
  # _EUID_OVERRIDE 仅供 bats 单测注入(bash 中 EUID 是 readonly)
  if [ "${_EUID_OVERRIDE:-${EUID:-$(id -u)}}" -ne 0 ]; then
    echo "ERROR: 必须以 root 运行(sudo)" >&2
    return 1
  fi
}

# detect_ubuntu [os-release-path]
# 输出 VERSION_CODENAME,非 Ubuntu 或缺少 codename 时非零退出
detect_ubuntu() {
  local os_release="${1:-/etc/os-release}"
  if [ ! -r "$os_release" ]; then
    echo "ERROR: 读不到 $os_release" >&2
    return 1
  fi
  local id codename
  id="$(awk -F= '$1=="ID"{gsub(/"/,"",$2); print $2}' "$os_release")"
  codename="$(awk -F= '$1=="VERSION_CODENAME"{gsub(/"/,"",$2); print $2}' "$os_release")"
  if [ "$id" != "ubuntu" ]; then
    echo "ERROR: 仅支持 Ubuntu,检测到 ID=$id" >&2
    return 1
  fi
  if [ -z "$codename" ]; then
    echo "ERROR: 缺少 VERSION_CODENAME" >&2
    return 1
  fi
  printf '%s\n' "$codename"
}
```

- [ ] **Step 4: 跑测试,确认 pass**

Run: `./tests/bats/run.sh`
Expected: 全部通过

- [ ] **Step 5: 提交**

```bash
git add install/lib/common.sh tests/bats/test_common_os.bats
git commit -m "common: add require_root and detect_ubuntu with tests"
```

---

## Task 3: lib/common.sh — 变量校验

**Files:**
- Modify: `install/lib/common.sh`
- Create: `tests/bats/test_common_vars.bats`

**目标:** 写 `require_vars` 函数,接受变量名列表,任一为空时报错列出所有缺失项。

- [ ] **Step 1: 写 failing test**

```bash
# tests/bats/test_common_vars.bats
#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
}

@test "require_vars passes when all set" {
  FOO=a BAR=b run require_vars FOO BAR
  [ "$status" -eq 0 ]
}

@test "require_vars fails when one missing, lists name" {
  FOO=a BAR="" run require_vars FOO BAR
  [ "$status" -ne 0 ]
  [[ "$output" == *"BAR"* ]]
}

@test "require_vars lists all missing names" {
  FOO="" BAR="" BAZ=ok run require_vars FOO BAR BAZ
  [ "$status" -ne 0 ]
  [[ "$output" == *"FOO"* ]]
  [[ "$output" == *"BAR"* ]]
  [[ "$output" != *"BAZ"* ]]
}

@test "require_vars treats unset as missing" {
  unset UNSET_VAR
  run require_vars UNSET_VAR
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNSET_VAR"* ]]
}
```

- [ ] **Step 2: 跑测试,确认 fail**

Run: `./tests/bats/run.sh`
Expected: `require_vars: command not found`

- [ ] **Step 3: 追加实现到 install/lib/common.sh**

```bash
# require_vars NAME1 NAME2 ...
# 任一变量为空或未设置则返回非零,列出全部缺失项
require_vars() {
  local missing=()
  local name
  for name in "$@"; do
    if [ -z "${!name:-}" ]; then
      missing+=("$name")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: 以下变量未设置:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    return 1
  fi
}
```

- [ ] **Step 4: 跑测试,确认 pass**

Run: `./tests/bats/run.sh`
Expected: 全部通过

- [ ] **Step 5: 提交**

```bash
git add install/lib/common.sh tests/bats/test_common_vars.bats
git commit -m "common: add require_vars helper"
```

---

## Task 4: lib/common.sh — 模板渲染 render_tpl

**Files:**
- Modify: `install/lib/common.sh`
- Create: `tests/bats/test_common_render.bats`

**目标:** 写 `render_tpl SRC DST KEY=VAL [KEY=VAL ...]`,把 `SRC` 中所有 `__KEY__` 占位符替换为对应值,写到 `DST`,渲染后扫描确保没有残留占位符(否则非零退出 — 这是 spec 验收第 6 条要求)。

实现细节:`sed` 在 value 含 `/` 时会炸,改用 awk 字符串替换。

- [ ] **Step 1: 写 failing test**

```bash
# tests/bats/test_common_render.bats
#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "render_tpl replaces single placeholder" {
  echo "hello __NAME__" > "$TMPDIR/in"
  run render_tpl "$TMPDIR/in" "$TMPDIR/out" "NAME=world"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMPDIR/out")" = "hello world" ]
}

@test "render_tpl replaces multiple keys" {
  printf 'a=__A__ b=__B__\n' > "$TMPDIR/in"
  run render_tpl "$TMPDIR/in" "$TMPDIR/out" "A=1" "B=2"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMPDIR/out")" = "a=1 b=2" ]
}

@test "render_tpl handles values containing slash and ampersand" {
  echo "url=__URL__" > "$TMPDIR/in"
  run render_tpl "$TMPDIR/in" "$TMPDIR/out" "URL=http://a/b&c=d"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMPDIR/out")" = "url=http://a/b&c=d" ]
}

@test "render_tpl fails when placeholder remains unreplaced" {
  printf 'x=__X__ y=__Y__\n' > "$TMPDIR/in"
  run render_tpl "$TMPDIR/in" "$TMPDIR/out" "X=1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"__Y__"* ]]
}

@test "render_tpl handles same placeholder appearing twice" {
  printf '__A__-__A__\n' > "$TMPDIR/in"
  run render_tpl "$TMPDIR/in" "$TMPDIR/out" "A=x"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMPDIR/out")" = "x-x" ]
}
```

- [ ] **Step 2: 跑测试,确认 fail**

Run: `./tests/bats/run.sh`

- [ ] **Step 3: 追加实现到 install/lib/common.sh**

```bash
# render_tpl SRC DST KEY=VAL [KEY=VAL ...]
# 把 SRC 中所有 __KEY__ 替换为 VAL,写到 DST。完成后扫描残留占位符,
# 残留即非零退出。值中可含 / & 等特殊字符(awk 字符串替换,非 sed)。
render_tpl() {
  local src="$1" dst="$2"
  shift 2
  if [ ! -r "$src" ]; then
    echo "ERROR: 模板不存在: $src" >&2
    return 1
  fi
  # 把 KEY=VAL 列表传给 awk
  local awk_kvs=()
  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    awk_kvs+=(-v "kv_$key=$val")
  done
  awk "${awk_kvs[@]}" '
    {
      line = $0
      for (var in ENVIRON) {}  # noop, force awk to be POSIX
      # 把所有 kv_XXX 形式的变量当作 __XXX__ 占位符
      for (k in SYMTAB) {
        if (k ~ /^kv_/) {
          ph = "__" substr(k, 4) "__"
          gsub(ph, SYMTAB[k], line)
        }
      }
      print line
    }
  ' "$src" > "$dst"

  # 残留占位符扫描
  local leftover
  leftover="$(grep -oE '__[A-Z][A-Z0-9_]*__' "$dst" | sort -u || true)"
  if [ -n "$leftover" ]; then
    echo "ERROR: 渲染后残留占位符:" >&2
    echo "$leftover" >&2
    return 1
  fi
}
```

注意:`SYMTAB` 是 gawk 扩展,Ubuntu 默认 `awk` 是 mawk,**不**支持 SYMTAB。改用更稳的实现:

```bash
render_tpl() {
  local src="$1" dst="$2"
  shift 2
  if [ ! -r "$src" ]; then
    echo "ERROR: 模板不存在: $src" >&2
    return 1
  fi
  # 拼出 awk 程序:每个 kv 一条 gsub
  local awk_prog='{ line=$0;'
  local kv key val awk_args=()
  local i=0
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    awk_args+=(-v "v${i}=$val")
    awk_prog+=" gsub(/__${key}__/, v${i}, line);"
    i=$((i+1))
  done
  awk_prog+=' print line; }'
  awk "${awk_args[@]}" "$awk_prog" "$src" > "$dst"

  local leftover
  leftover="$(grep -oE '__[A-Z][A-Z0-9_]*__' "$dst" | sort -u || true)"
  if [ -n "$leftover" ]; then
    echo "ERROR: 渲染后残留占位符:" >&2
    echo "$leftover" >&2
    return 1
  fi
}
```

**用这一版**(基于 `-v` 变量,与 mawk 兼容)。

- [ ] **Step 4: 跑测试,确认 pass**

Run: `./tests/bats/run.sh`

- [ ] **Step 5: 提交**

```bash
git add install/lib/common.sh tests/bats/test_common_render.bats
git commit -m "common: add render_tpl with placeholder leak detection"
```

---

## Task 5: install.sh — 参数解析与 whiptail 菜单 dispatch

**Files:**
- Modify: `install/install.sh`
- Create: `install/services/_stub.sh`(临时存根,用于测试 dispatch)
- Create: `tests/bats/test_install_dispatch.bats`

**目标:** 主入口解析 `install|reconfigure <服务...>`;无服务名且终端可交互 → whiptail 多选;无服务名且非交互 → 报错退出;未知服务名 → 报错列出已知服务名。每个服务调用 `services/<name>.sh::do_<action>`。

存根 `_stub.sh` 用来在 bats 里模拟服务模块,无需依赖任何真实服务实现。

- [ ] **Step 1: 写存根 services/_stub.sh**

```bash
#!/usr/bin/env bash
# 仅用于测试:把调用记录到 $STUB_LOG
do_install()     { echo "stub:install" >> "$STUB_LOG"; }
do_reconfigure() { echo "stub:reconfigure" >> "$STUB_LOG"; }
do_health()      { echo "stub:health" >> "$STUB_LOG"; }
```

- [ ] **Step 2: 写 failing test**

```bash
# tests/bats/test_install_dispatch.bats
#!/usr/bin/env bats
load 'helpers'

setup() {
  TMPDIR="$(mktemp -d)"
  export STUB_LOG="$TMPDIR/log"
  : > "$STUB_LOG"
  # 让 install.sh 用 stub 当作 fake kamailio/rtpengine/caddy 模块
  STUB_SVC_DIR="$TMPDIR/services"
  mkdir -p "$STUB_SVC_DIR"
  for s in kamailio rtpengine caddy; do
    cp "$REPO_ROOT/install/services/_stub.sh" "$STUB_SVC_DIR/$s.sh"
  done
  export INSTALL_SERVICES_DIR="$STUB_SVC_DIR"
  # bypass root 校验
  export SKIP_ROOT_CHECK=1
  # bypass OS 校验
  export SKIP_OS_CHECK=1
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "no subcommand exits non-zero" {
  run "$REPO_ROOT/install/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"用法"* ]]
}

@test "install kamailio dispatches to kamailio do_install" {
  run "$REPO_ROOT/install/install.sh" install kamailio
  [ "$status" -eq 0 ]
  grep -q "stub:install" "$STUB_LOG"
}

@test "reconfigure caddy dispatches to caddy do_reconfigure" {
  run "$REPO_ROOT/install/install.sh" reconfigure caddy
  [ "$status" -eq 0 ]
  grep -q "stub:reconfigure" "$STUB_LOG"
}

@test "install with unknown service exits non-zero and lists known" {
  run "$REPO_ROOT/install/install.sh" install nonesuch
  [ "$status" -ne 0 ]
  [[ "$output" == *"kamailio"* ]]
  [[ "$output" == *"rtpengine"* ]]
  [[ "$output" == *"caddy"* ]]
}

@test "install with no service in non-tty exits with hint" {
  run bash -c "'$REPO_ROOT/install/install.sh' install </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"显式"* || "$output" == *"non-interactive"* ]]
}

@test "install with multiple services dispatches each" {
  run "$REPO_ROOT/install/install.sh" install kamailio caddy
  [ "$status" -eq 0 ]
  [ "$(grep -c 'stub:install' "$STUB_LOG")" -eq 2 ]
}
```

- [ ] **Step 3: 跑测试,确认 fail**

Run: `./tests/bats/run.sh`
Expected: install.sh 当前空,所有 dispatch 测试 fail

- [ ] **Step 4: 实现 install/install.sh**

```bash
#!/usr/bin/env bash
# install/install.sh — 主入口
set -euo pipefail
trap 'echo "[FAIL] line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
SERVICES_DIR="${INSTALL_SERVICES_DIR:-$SCRIPT_DIR/services}"

# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

KNOWN_SERVICES=(kamailio rtpengine caddy)

usage() {
  cat <<EOF
用法: $0 <install|reconfigure> [service ...]

已知服务: ${KNOWN_SERVICES[*]}

不传服务名时弹出多选菜单(需要交互终端)。
非交互终端必须显式列出服务名。
EOF
}

is_known_service() {
  local s="$1"
  for k in "${KNOWN_SERVICES[@]}"; do
    [ "$s" = "$k" ] && return 0
  done
  return 1
}

pick_services_via_menu() {
  # 输出选中的服务名,空格分隔
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "ERROR: 非交互终端下必须显式列出服务名(non-interactive)" >&2
    return 1
  fi
  if ! command -v whiptail >/dev/null 2>&1; then
    echo "ERROR: 缺少 whiptail(apt install whiptail)" >&2
    return 1
  fi
  local args=() s
  for s in "${KNOWN_SERVICES[@]}"; do
    args+=("$s" "" "ON")
  done
  local selected
  selected="$(whiptail --title "选择服务" \
    --checklist "用空格勾选,Tab 切到 OK,回车确认" 15 50 5 \
    "${args[@]}" 3>&1 1>&2 2>&3)" || return 1
  # whiptail 输出形如 "kamailio" "caddy",含引号
  echo "$selected" | tr -d '"'
}

do_dispatch() {
  local action="$1"; shift
  local services=("$@")
  if [ "${#services[@]}" -eq 0 ]; then
    local picked
    picked="$(pick_services_via_menu)" || return 1
    # shellcheck disable=SC2206
    services=($picked)
    if [ "${#services[@]}" -eq 0 ]; then
      echo "ERROR: 未选择任何服务" >&2
      return 1
    fi
  fi
  local s
  for s in "${services[@]}"; do
    if ! is_known_service "$s"; then
      echo "ERROR: 未知服务 '$s';已知: ${KNOWN_SERVICES[*]}" >&2
      return 1
    fi
  done
  for s in "${services[@]}"; do
    echo ">>> ${action}: $s"
    # 子 shell 隔离每个服务的函数定义
    (
      # shellcheck source=/dev/null
      source "$SERVICES_DIR/$s.sh"
      "do_${action}"
    )
  done
}

main() {
  if [ "$#" -eq 0 ]; then
    usage >&2
    return 2
  fi
  local action="$1"; shift
  case "$action" in
    install|reconfigure) ;;
    -h|--help) usage; return 0 ;;
    *) usage >&2; return 2 ;;
  esac

  # root / OS 校验,允许测试 bypass
  if [ "${SKIP_ROOT_CHECK:-0}" != "1" ]; then
    require_root
  fi
  if [ "${SKIP_OS_CHECK:-0}" != "1" ]; then
    UBUNTU_CODENAME="$(detect_ubuntu)"
    export UBUNTU_CODENAME
  fi

  do_dispatch "$action" "$@"
}

main "$@"
```

- [ ] **Step 5: 跑测试,确认 pass**

Run: `./tests/bats/run.sh`
Expected: 全部通过

- [ ] **Step 6: 提交**

```bash
git add install/install.sh install/services/_stub.sh tests/bats/test_install_dispatch.bats
git commit -m "install: param parsing + whiptail menu dispatch"
```

---

## Task 6: services/caddy.sh + Caddyfile.tpl + drop-in

**Files:**
- Create: `install/services/caddy.sh`
- Create: `install/conf/caddy/Caddyfile.tpl`
- Create: `install/systemd/caddy.service.d/override.conf`
- Create: `tests/bats/test_caddy_render.bats`

**目标:** 实现 caddy 服务模块,渲染逻辑用 bats 覆盖;真包安装步骤明文写在脚本里,人工 smoke 验。

Caddy 选作第一个落地的服务,因为最简单(不需要内核模块、不需要业务 lua),先打通"模板渲染 + apt 源 + systemd drop-in + enable --now"主流程。

- [ ] **Step 1: 写 install/conf/caddy/Caddyfile.tpl**

```caddy
__CADDY_API_DOMAIN__ {
  reverse_proxy __CADDY_API_UPSTREAM__
}
__CADDY_APP_DOMAIN__ {
  reverse_proxy __CADDY_APP_UPSTREAM__
}
__CADDY_WEBRTC_DOMAIN__ {
  @ws {
    header Connection *Upgrade*
    header Upgrade websocket
  }
  handle @ws {
    reverse_proxy __CADDY_WEBRTC_UPSTREAM__
  }
  handle {
    respond "WebSocket Only" 400
  }
}
```

- [ ] **Step 2: 写 install/systemd/caddy.service.d/override.conf**

```ini
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Restart=always
RestartSec=3
LimitNOFILE=65535
```

- [ ] **Step 3: 写 failing test(渲染层)**

```bash
# tests/bats/test_caddy_render.bats
#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "Caddyfile renders all placeholders" {
  run render_tpl "$REPO_ROOT/install/conf/caddy/Caddyfile.tpl" "$TMPDIR/Caddyfile" \
    "CADDY_API_DOMAIN=api.test" \
    "CADDY_API_UPSTREAM=localhost:8080" \
    "CADDY_APP_DOMAIN=app.test" \
    "CADDY_APP_UPSTREAM=localhost:3000" \
    "CADDY_WEBRTC_DOMAIN=ws.test" \
    "CADDY_WEBRTC_UPSTREAM=127.0.0.1:15062"
  [ "$status" -eq 0 ]
  grep -q "api.test" "$TMPDIR/Caddyfile"
  grep -q "localhost:8080" "$TMPDIR/Caddyfile"
  grep -q "ws.test" "$TMPDIR/Caddyfile"
  grep -q "127.0.0.1:15062" "$TMPDIR/Caddyfile"
  ! grep -q "__CADDY_" "$TMPDIR/Caddyfile"
}

@test "Caddyfile missing one var fails with leak detection" {
  run render_tpl "$REPO_ROOT/install/conf/caddy/Caddyfile.tpl" "$TMPDIR/Caddyfile" \
    "CADDY_API_DOMAIN=api.test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"__CADDY_"* ]]
}
```

- [ ] **Step 4: 跑测试,确认 render 测试通过(已有 render_tpl)**

Run: `./tests/bats/run.sh tests/bats/test_caddy_render.bats`
Expected: 通过

- [ ] **Step 5: 写 install/services/caddy.sh**

```bash
#!/usr/bin/env bash
# install/services/caddy.sh
# 暴露 do_install / do_reconfigure / do_health,被 install.sh 在子 shell 中 source。
# 依赖:已 source common.sh、UBUNTU_CODENAME 已导出。

# ===== 必填变量(由主仓库 install.sh 顶部或环境注入) =====
: "${CADDY_API_DOMAIN:=}"
: "${CADDY_API_UPSTREAM:=}"
: "${CADDY_APP_DOMAIN:=}"
: "${CADDY_APP_UPSTREAM:=}"
: "${CADDY_WEBRTC_DOMAIN:=}"
: "${CADDY_WEBRTC_UPSTREAM:=}"

_caddy_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

_caddy_check_vars() {
  require_vars \
    CADDY_API_DOMAIN CADDY_API_UPSTREAM \
    CADDY_APP_DOMAIN CADDY_APP_UPSTREAM \
    CADDY_WEBRTC_DOMAIN CADDY_WEBRTC_UPSTREAM
}

_caddy_add_repo() {
  install -d -m 0755 /etc/apt/keyrings
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  chmod 0644 /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
}

_caddy_render() {
  local repo dst="/etc/caddy/Caddyfile"
  repo="$(_caddy_repo_root)"
  install -d -m 0755 /etc/caddy
  render_tpl "$repo/conf/caddy/Caddyfile.tpl" "$dst" \
    "CADDY_API_DOMAIN=$CADDY_API_DOMAIN" \
    "CADDY_API_UPSTREAM=$CADDY_API_UPSTREAM" \
    "CADDY_APP_DOMAIN=$CADDY_APP_DOMAIN" \
    "CADDY_APP_UPSTREAM=$CADDY_APP_UPSTREAM" \
    "CADDY_WEBRTC_DOMAIN=$CADDY_WEBRTC_DOMAIN" \
    "CADDY_WEBRTC_UPSTREAM=$CADDY_WEBRTC_UPSTREAM"
  chown caddy:caddy "$dst"
  chmod 644 "$dst"
  caddy fmt --overwrite "$dst"
  caddy validate --config "$dst"
}

_caddy_install_dropin() {
  local repo
  repo="$(_caddy_repo_root)"
  install -d -m 0755 /etc/systemd/system/caddy.service.d
  install -m 0644 "$repo/systemd/caddy.service.d/override.conf" \
    /etc/systemd/system/caddy.service.d/override.conf
  systemctl daemon-reload
}

do_install() {
  _caddy_check_vars
  _caddy_add_repo
  apt-get install -y caddy
  _caddy_render
  _caddy_install_dropin
  systemctl enable --now caddy
  sleep 3
  systemctl is-active caddy >/dev/null || {
    journalctl -u caddy -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_reconfigure() {
  _caddy_check_vars
  _caddy_render
  _caddy_install_dropin
  systemctl restart caddy
  sleep 2
  systemctl is-active caddy >/dev/null || {
    journalctl -u caddy -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_health() {
  echo "--- caddy ---"
  caddy version || true
  systemctl is-active caddy
  systemctl is-enabled caddy
  ss -lntp 2>/dev/null | grep -E ':80|:443' || echo "(80/443 未在监听)"
}
```

- [ ] **Step 6: 跑全套 bats**

Run: `./tests/bats/run.sh`
Expected: 全部通过(render 已通过,真包安装步骤靠真机 smoke 验)

- [ ] **Step 7: 提交**

```bash
git add install/services/caddy.sh install/conf/caddy/ install/systemd/caddy.service.d/ tests/bats/test_caddy_render.bats
git commit -m "caddy: service module with Caddyfile template + drop-in"
```

---

## Task 7: services/rtpengine.sh + 模板 + drop-in + 内核模块

**Files:**
- Create: `install/services/rtpengine.sh`
- Create: `install/conf/rtpengine/rtpengine.conf.tpl`
- Create: `install/systemd/rtpengine-daemon.service.d/override.conf`
- Create: `tests/bats/test_rtpengine_render.bats`

**目标:** 与 caddy 模块同形,额外:加 sipwise apt 源、跑 `apt-cache madison` 探测 mr12.5.1 在当前 codename 是否可用、加载 `xt_RTPENGINE` 内核模块并写 `/etc/modules-load.d/`。

- [ ] **Step 1: 写 install/conf/rtpengine/rtpengine.conf.tpl**

```ini
[rtpengine]
table = -1
interface = priv/__PRIVATE_IP__;pub/__PRIVATE_IP__!__PUBLIC_IP__
listen-ng = 0.0.0.0:__RTPE_NG_PORT__
port-min = __RTPE_PORT_MIN__
port-max = __RTPE_PORT_MAX__
log-stderr = true
log-level = 6
offer-timeout = 120
```

- [ ] **Step 2: 写 install/systemd/rtpengine-daemon.service.d/override.conf**

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

- [ ] **Step 3: 写 failing test(渲染层)**

```bash
# tests/bats/test_rtpengine_render.bats
#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TMPDIR="$(mktemp -d)"
}

teardown() { rm -rf "$TMPDIR"; }

@test "rtpengine.conf renders all placeholders" {
  run render_tpl "$REPO_ROOT/install/conf/rtpengine/rtpengine.conf.tpl" "$TMPDIR/out" \
    "PRIVATE_IP=10.0.0.1" "PUBLIC_IP=1.2.3.4" \
    "RTPE_NG_PORT=2223" "RTPE_PORT_MIN=40000" "RTPE_PORT_MAX=60000"
  [ "$status" -eq 0 ]
  grep -q "priv/10.0.0.1;pub/10.0.0.1!1.2.3.4" "$TMPDIR/out"
  grep -q "listen-ng = 0.0.0.0:2223" "$TMPDIR/out"
  grep -q "port-min = 40000" "$TMPDIR/out"
  ! grep -q "__" "$TMPDIR/out"
}

@test "rtpengine.conf missing PUBLIC_IP fails" {
  run render_tpl "$REPO_ROOT/install/conf/rtpengine/rtpengine.conf.tpl" "$TMPDIR/out" \
    "PRIVATE_IP=10.0.0.1" \
    "RTPE_NG_PORT=2223" "RTPE_PORT_MIN=40000" "RTPE_PORT_MAX=60000"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 4: 跑测试**

Run: `./tests/bats/run.sh tests/bats/test_rtpengine_render.bats`
Expected: 通过

- [ ] **Step 5: 写 install/services/rtpengine.sh**

```bash
#!/usr/bin/env bash
# install/services/rtpengine.sh

: "${PUBLIC_IP:=}"
: "${PRIVATE_IP:=}"
: "${RTPE_NG_PORT:=2223}"
: "${RTPE_PORT_MIN:=40000}"
: "${RTPE_PORT_MAX:=60000}"
: "${RTPENGINE_RELEASE:=mr12.5.1}"

_rtpe_repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

_rtpe_check_vars() {
  require_vars PUBLIC_IP PRIVATE_IP RTPE_NG_PORT RTPE_PORT_MIN RTPE_PORT_MAX RTPENGINE_RELEASE UBUNTU_CODENAME
}

_rtpe_add_repo() {
  install -d -m 0755 /etc/apt/keyrings
  wget -qO- 'https://deb.sipwise.com/spce/keyring/sipwise-keyring-bootstrap.gpg' \
    | gpg --dearmor -o /etc/apt/keyrings/sipwise.gpg
  chmod 0644 /etc/apt/keyrings/sipwise.gpg
  cat > /etc/apt/sources.list.d/sipwise.list <<EOF
deb [signed-by=/etc/apt/keyrings/sipwise.gpg] https://deb.sipwise.com/spce/${RTPENGINE_RELEASE}/ ${UBUNTU_CODENAME} main
EOF
  apt-get update
  if ! apt-cache madison ngcp-rtpengine | grep -q .; then
    echo "ERROR: sipwise 仓库在 codename=${UBUNTU_CODENAME}、release=${RTPENGINE_RELEASE} 下没有 ngcp-rtpengine 包" >&2
    return 1
  fi
}

_rtpe_install_pkgs() {
  apt-get install -y dkms "linux-headers-$(uname -r)"
  apt-get install -y ngcp-rtpengine ngcp-rtpengine-kernel-dkms
}

_rtpe_load_kernel_mod() {
  modprobe xt_RTPENGINE
  echo "xt_RTPENGINE" > /etc/modules-load.d/rtpengine.conf
  lsmod | grep -q xt_RTPENGINE || {
    echo "ERROR: xt_RTPENGINE 未加载" >&2
    return 1
  }
}

_rtpe_render() {
  local repo dst="/etc/rtpengine/rtpengine.conf"
  repo="$(_rtpe_repo_root)"
  install -d -m 0755 /etc/rtpengine
  render_tpl "$repo/conf/rtpengine/rtpengine.conf.tpl" "$dst" \
    "PRIVATE_IP=$PRIVATE_IP" \
    "PUBLIC_IP=$PUBLIC_IP" \
    "RTPE_NG_PORT=$RTPE_NG_PORT" \
    "RTPE_PORT_MIN=$RTPE_PORT_MIN" \
    "RTPE_PORT_MAX=$RTPE_PORT_MAX"
  chown rtpengine:rtpengine "$dst"
  chmod 640 "$dst"
}

_rtpe_install_dropin() {
  local repo
  repo="$(_rtpe_repo_root)"
  install -d -m 0755 /etc/systemd/system/rtpengine-daemon.service.d
  install -m 0644 "$repo/systemd/rtpengine-daemon.service.d/override.conf" \
    /etc/systemd/system/rtpengine-daemon.service.d/override.conf
  systemctl daemon-reload
}

do_install() {
  _rtpe_check_vars
  _rtpe_add_repo
  _rtpe_install_pkgs
  _rtpe_load_kernel_mod
  _rtpe_render
  _rtpe_install_dropin
  systemctl enable --now rtpengine-daemon
  sleep 3
  systemctl is-active rtpengine-daemon >/dev/null || {
    journalctl -u rtpengine-daemon -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_reconfigure() {
  _rtpe_check_vars
  _rtpe_render
  _rtpe_install_dropin
  systemctl restart rtpengine-daemon
  sleep 2
  systemctl is-active rtpengine-daemon >/dev/null || {
    journalctl -u rtpengine-daemon -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_health() {
  echo "--- rtpengine ---"
  rtpengine --version 2>/dev/null | head -1 || true
  lsmod | grep xt_RTPENGINE || echo "(xt_RTPENGINE 未加载)"
  systemctl is-active rtpengine-daemon
  systemctl is-enabled rtpengine-daemon
  ss -lnup 2>/dev/null | grep ":${RTPE_NG_PORT}" || echo "(NG 端口 ${RTPE_NG_PORT} 未在监听)"
}
```

- [ ] **Step 6: 跑全套 bats**

Run: `./tests/bats/run.sh`
Expected: 全部通过

- [ ] **Step 7: 提交**

```bash
git add install/services/rtpengine.sh install/conf/rtpengine/ install/systemd/rtpengine-daemon.service.d/ tests/bats/test_rtpengine_render.bats
git commit -m "rtpengine: service module with sipwise repo + in-kernel mode"
```

---

## Task 8: services/kamailio.sh + 模板 + drop-in

**Files:**
- Create: `install/services/kamailio.sh`
- Create: `install/conf/kamailio/kamailio.cfg.tpl`
- Create: `install/conf/kamailio/kamailio.lua`(从参考目录拷贝)
- Create: `install/conf/kamailio/dispatcher.list`(从参考目录拷贝)
- Create: `install/systemd/kamailio.service.d/override.conf`
- Create: `tests/bats/test_kamailio_render.bats`

**目标:** 与前两个服务同形,额外:加 kamailio 官方 apt 源、网卡校验、`RUN_KAMAILIO=yes`、`kamailio.lua` 与 `dispatcher.list` 原样拷贝。

- [ ] **Step 1: 从参考目录拷贝 kamailio.lua 和 dispatcher.list**

```bash
cp ~/data/project/mygithub/aicallcenter-deploy/kamailio/conf/kamailio.lua install/conf/kamailio/kamailio.lua
cp ~/data/project/mygithub/aicallcenter-deploy/kamailio/conf/dispatcher.list install/conf/kamailio/dispatcher.list
```

- [ ] **Step 2: 写 install/conf/kamailio/kamailio.cfg.tpl**

从参考目录 `~/data/project/mygithub/aicallcenter-deploy/kamailio/conf/kamailio.cfg` 拷贝,然后替换为占位符:

```bash
cp ~/data/project/mygithub/aicallcenter-deploy/kamailio/conf/kamailio.cfg install/conf/kamailio/kamailio.cfg.tpl
```

然后手工编辑 `install/conf/kamailio/kamailio.cfg.tpl`,把以下行改为占位符:

```diff
- #!define DBURL "mysql://__DB_USER__:__DB_PASS__@__DB_HOST__:__DB_PORT__/__DB_NAME__"
- #!define REDISURL "name=srvN;addr=__REDIS_HOST__;port=__REDIS_PORT__;pass=__REDIS_PASS__;db=0"
```
(这两行参考里已经是占位符形式,保持不变即可)

```diff
- alias="soft.voicelen.cn"
- alias="webrtc.voicelen.cn"
+ alias="__KAM_ALIAS_1__"
+ alias="__KAM_ALIAS_2__"
- listen=udp:eth0:15060 advertise 82.157.103.207:15060
- listen=tcp:eth0:15062
+ listen=udp:__LISTEN_IFACE__:__SIP_UDP_PORT__ advertise __PUBLIC_IP__:__SIP_UDP_PORT__
+ listen=tcp:__LISTEN_IFACE__:__SIP_TCP_PORT__
- modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:2223")
+ modparam("rtpengine", "rtpengine_sock", "udp:127.0.0.1:__RTPE_NG_PORT__")
```

不动 `__DB_*__ / __REDIS_*__`(原文已是占位符)。

- [ ] **Step 3: 写 install/systemd/kamailio.service.d/override.conf**

```ini
[Unit]
After=network-online.target rtpengine-daemon.service
Wants=network-online.target

[Service]
Restart=always
RestartSec=3
LimitNOFILE=65535
LimitNPROC=65535
LimitCORE=infinity
```

(不写 Requires,见 spec §8.2)

- [ ] **Step 4: 写 failing test**

```bash
# tests/bats/test_kamailio_render.bats
#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TMPDIR="$(mktemp -d)"
}
teardown() { rm -rf "$TMPDIR"; }

@test "kamailio.cfg renders all placeholders" {
  run render_tpl "$REPO_ROOT/install/conf/kamailio/kamailio.cfg.tpl" "$TMPDIR/cfg" \
    "PUBLIC_IP=1.2.3.4" "PRIVATE_IP=10.0.0.1" "LISTEN_IFACE=eth0" \
    "SIP_UDP_PORT=15060" "SIP_TCP_PORT=15062" \
    "KAM_ALIAS_1=a.test" "KAM_ALIAS_2=b.test" \
    "DB_HOST=db.host" "DB_PORT=3306" "DB_USER=u" "DB_PASS=p" "DB_NAME=n" \
    "REDIS_HOST=r.host" "REDIS_PORT=6379" "REDIS_PASS=pw" \
    "RTPE_NG_PORT=2223"
  [ "$status" -eq 0 ]
  grep -q 'listen=udp:eth0:15060 advertise 1.2.3.4:15060' "$TMPDIR/cfg"
  grep -q 'alias="a.test"' "$TMPDIR/cfg"
  grep -q 'mysql://u:p@db.host:3306/n' "$TMPDIR/cfg"
  grep -q 'addr=r.host;port=6379;pass=pw' "$TMPDIR/cfg"
  grep -q 'udp:127.0.0.1:2223' "$TMPDIR/cfg"
  ! grep -qE '__[A-Z_]+__' "$TMPDIR/cfg"
}

@test "kamailio.cfg missing DB_PASS fails" {
  run render_tpl "$REPO_ROOT/install/conf/kamailio/kamailio.cfg.tpl" "$TMPDIR/cfg" \
    "PUBLIC_IP=1.2.3.4" "PRIVATE_IP=10.0.0.1" "LISTEN_IFACE=eth0" \
    "SIP_UDP_PORT=15060" "SIP_TCP_PORT=15062" \
    "KAM_ALIAS_1=a.test" "KAM_ALIAS_2=b.test" \
    "DB_HOST=db.host" "DB_PORT=3306" "DB_USER=u" "DB_NAME=n" \
    "REDIS_HOST=r.host" "REDIS_PORT=6379" "REDIS_PASS=pw" \
    "RTPE_NG_PORT=2223"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 5: 跑测试,确认通过**

Run: `./tests/bats/run.sh tests/bats/test_kamailio_render.bats`

- [ ] **Step 6: 写 install/services/kamailio.sh**

```bash
#!/usr/bin/env bash
# install/services/kamailio.sh

: "${PUBLIC_IP:=}"; : "${PRIVATE_IP:=}"; : "${LISTEN_IFACE:=eth0}"
: "${SIP_UDP_PORT:=15060}"; : "${SIP_TCP_PORT:=15062}"
: "${KAM_ALIAS_1:=}"; : "${KAM_ALIAS_2:=}"
: "${DB_HOST:=}"; : "${DB_PORT:=3306}"; : "${DB_USER:=}"; : "${DB_PASS:=}"; : "${DB_NAME:=}"
: "${REDIS_HOST:=}"; : "${REDIS_PORT:=6379}"; : "${REDIS_PASS:=}"
: "${RTPE_NG_PORT:=2223}"
: "${KAMAILIO_BRANCH:=58}"

_kam_repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

_kam_check_vars() {
  require_vars \
    PUBLIC_IP PRIVATE_IP LISTEN_IFACE SIP_UDP_PORT SIP_TCP_PORT \
    KAM_ALIAS_1 KAM_ALIAS_2 \
    DB_HOST DB_PORT DB_USER DB_PASS DB_NAME \
    REDIS_HOST REDIS_PORT \
    RTPE_NG_PORT KAMAILIO_BRANCH UBUNTU_CODENAME
}

_kam_check_iface() {
  ip -o link show "$LISTEN_IFACE" >/dev/null 2>&1 || {
    echo "ERROR: 网卡 $LISTEN_IFACE 不存在" >&2
    return 1
  }
  ip -o -4 addr show "$LISTEN_IFACE" | grep -q "${PRIVATE_IP}/" || {
    echo "ERROR: PRIVATE_IP=$PRIVATE_IP 未绑定在 $LISTEN_IFACE" >&2
    return 1
  }
}

_kam_add_repo() {
  install -d -m 0755 /etc/apt/keyrings
  wget -qO- "http://deb.kamailio.org/kamailiodebkey.gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/kamailio.gpg
  chmod 0644 /etc/apt/keyrings/kamailio.gpg
  cat > /etc/apt/sources.list.d/kamailio.list <<EOF
deb [signed-by=/etc/apt/keyrings/kamailio.gpg] http://deb.kamailio.org/kamailio${KAMAILIO_BRANCH} ${UBUNTU_CODENAME} main
EOF
  apt-get update
}

_kam_install_pkgs() {
  apt-get install -y \
    kamailio \
    kamailio-mysql-modules \
    kamailio-redis-modules \
    kamailio-tls-modules \
    kamailio-websocket-modules \
    kamailio-presence-modules \
    kamailio-json-modules \
    kamailio-xmpp-modules \
    kamailio-utils-modules \
    kamailio-extra-modules
  # 默认 disable 的坑
  sed -i 's/^#*RUN_KAMAILIO=.*/RUN_KAMAILIO=yes/' /etc/default/kamailio
}

_kam_render() {
  local repo
  repo="$(_kam_repo_root)"
  install -d -m 0755 /etc/kamailio
  render_tpl "$repo/conf/kamailio/kamailio.cfg.tpl" /etc/kamailio/kamailio.cfg \
    "PUBLIC_IP=$PUBLIC_IP" "PRIVATE_IP=$PRIVATE_IP" "LISTEN_IFACE=$LISTEN_IFACE" \
    "SIP_UDP_PORT=$SIP_UDP_PORT" "SIP_TCP_PORT=$SIP_TCP_PORT" \
    "KAM_ALIAS_1=$KAM_ALIAS_1" "KAM_ALIAS_2=$KAM_ALIAS_2" \
    "DB_HOST=$DB_HOST" "DB_PORT=$DB_PORT" "DB_USER=$DB_USER" "DB_PASS=$DB_PASS" "DB_NAME=$DB_NAME" \
    "REDIS_HOST=$REDIS_HOST" "REDIS_PORT=$REDIS_PORT" "REDIS_PASS=$REDIS_PASS" \
    "RTPE_NG_PORT=$RTPE_NG_PORT"
  install -m 0644 -o kamailio -g kamailio "$repo/conf/kamailio/kamailio.lua" /etc/kamailio/kamailio.lua
  install -m 0644 -o kamailio -g kamailio "$repo/conf/kamailio/dispatcher.list" /etc/kamailio/dispatcher.list
  chown kamailio:kamailio /etc/kamailio/kamailio.cfg
  chmod 640 /etc/kamailio/kamailio.cfg
}

_kam_install_dropin() {
  local repo
  repo="$(_kam_repo_root)"
  install -d -m 0755 /etc/systemd/system/kamailio.service.d
  install -m 0644 "$repo/systemd/kamailio.service.d/override.conf" \
    /etc/systemd/system/kamailio.service.d/override.conf
  systemctl daemon-reload
}

do_install() {
  _kam_check_vars
  _kam_check_iface
  _kam_add_repo
  _kam_install_pkgs
  _kam_render
  _kam_install_dropin
  systemctl enable --now kamailio
  sleep 3
  systemctl is-active kamailio >/dev/null || {
    journalctl -u kamailio -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_reconfigure() {
  _kam_check_vars
  _kam_check_iface
  _kam_render
  _kam_install_dropin
  systemctl restart kamailio
  sleep 2
  systemctl is-active kamailio >/dev/null || {
    journalctl -u kamailio -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_health() {
  echo "--- kamailio ---"
  kamailio -v 2>/dev/null | head -1 || true
  systemctl is-active kamailio
  systemctl is-enabled kamailio
  ss -lnup 2>/dev/null | grep ":${SIP_UDP_PORT}" || echo "(UDP ${SIP_UDP_PORT} 未在监听)"
  ss -lntp 2>/dev/null | grep ":${SIP_TCP_PORT}" || echo "(TCP ${SIP_TCP_PORT} 未在监听)"
}
```

- [ ] **Step 7: 跑全套 bats**

Run: `./tests/bats/run.sh`
Expected: 全部通过

- [ ] **Step 8: 提交**

```bash
git add install/services/kamailio.sh install/conf/kamailio/ install/systemd/kamailio.service.d/ tests/bats/test_kamailio_render.bats
git commit -m "kamailio: service module with kamailio.cfg template + lua/dispatcher"
```

---

## Task 9: 端到端 dispatch 测试 — 多服务联动

**Files:**
- Modify: `tests/bats/test_install_dispatch.bats`

**目标:** 上一版 dispatch 测试是用 `_stub.sh` 跑的。现在所有真实服务模块已就位,**追加一组测试**:把 `do_install` 等函数 mock 成只打 log,确保主入口能正确调用真实服务模块文件而不是 stub。

- [ ] **Step 1: 在 test_install_dispatch.bats 末尾追加**

```bash
@test "install all dispatches kamailio rtpengine caddy via menu autopick" {
  # 模拟交互式终端 + 自动选中全部
  # whiptail 不可用时跳过(CI 容器里通常没装)
  command -v whiptail >/dev/null 2>&1 || skip "whiptail 不可用"
  # 这条测试需要 expect/真实 tty,作为占位;真机 smoke 验证
  skip "需要交互式终端 + whiptail"
}

@test "real services dir loads each service.sh without syntax error" {
  for s in kamailio rtpengine caddy; do
    run bash -n "$REPO_ROOT/install/services/$s.sh"
    [ "$status" -eq 0 ]
  done
}

@test "real services dir defines do_install / do_reconfigure / do_health" {
  for s in kamailio rtpengine caddy; do
    run bash -c "source '$REPO_ROOT/install/lib/common.sh'; source '$REPO_ROOT/install/services/$s.sh'; declare -F do_install do_reconfigure do_health"
    [ "$status" -eq 0 ]
    [[ "$output" == *"do_install"* ]]
    [[ "$output" == *"do_reconfigure"* ]]
    [[ "$output" == *"do_health"* ]]
  done
}
```

- [ ] **Step 2: 跑测试**

Run: `./tests/bats/run.sh`
Expected: 全部通过,whiptail 那条 skip

- [ ] **Step 3: 提交**

```bash
git add tests/bats/test_install_dispatch.bats
git commit -m "test: verify real service modules define expected interface"
```

---

## Task 10: 顶层 README 与必填变量样例文件

**Files:**
- Create: `install/install.env.example`
- Create: `install/README.md`

**目标:** 让用户能照着说明把 `install.env.example` 拷为 `install.env`,改完后跑 `sudo ./install/install.sh install`(或 `sudo -E env $(cat install/install.env | xargs) ./install/install.sh ...`)。

- [ ] **Step 1: 写 install/install.env.example**

```bash
# 拷为 install/install.env,填好变量后:
#   set -a; source install/install.env; set +a
#   sudo -E ./install/install.sh install

# ===== 网络(kamailio + rtpengine 必填) =====
PUBLIC_IP=""
PRIVATE_IP=""
LISTEN_IFACE="eth0"

# ===== kamailio SIP 监听(kamailio 必填) =====
SIP_UDP_PORT="15060"
SIP_TCP_PORT="15062"
KAM_ALIAS_1="soft.voicelen.cn"
KAM_ALIAS_2="webrtc.voicelen.cn"

# ===== MySQL(kamailio 必填,异机) =====
DB_HOST=""
DB_PORT="3306"
DB_USER=""
DB_PASS=""
DB_NAME=""

# ===== Redis(kamailio 必填,异机) =====
REDIS_HOST=""
REDIS_PORT="6379"
REDIS_PASS=""

# ===== rtpengine 必填 =====
RTPE_NG_PORT="2223"
RTPE_PORT_MIN="40000"
RTPE_PORT_MAX="60000"

# ===== caddy 必填 =====
CADDY_API_DOMAIN="api.voicelen.cn"
CADDY_API_UPSTREAM="localhost:18080"
CADDY_APP_DOMAIN="app.voicelen.cn"
CADDY_APP_UPSTREAM="localhost:13000"
CADDY_WEBRTC_DOMAIN="webrtc.voicelen.cn"
CADDY_WEBRTC_UPSTREAM="127.0.0.1:15062"

# ===== 可选 =====
KAMAILIO_BRANCH="58"
RTPENGINE_RELEASE="mr12.5.1"
```

- [ ] **Step 2: 写 install/README.md**

```markdown
# SBC 宿主机一键安装

支持 **kamailio 5.8 / rtpengine 12.5.1 (in-kernel) / caddy**,Ubuntu(任意版本)。

## 用法

```bash
cp install/install.env.example install/install.env
# 编辑 install.env 填好变量

set -a; source install/install.env; set +a
sudo -E ./install/install.sh install
# 弹出 whiptail 多选菜单,空格勾选,回车确认
```

只装某个服务:

```bash
sudo -E ./install/install.sh install caddy
sudo -E ./install/install.sh install kamailio rtpengine
```

重渲配置(不动包):

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

只装某个服务时,无关变量留空即可。

## 验收(每次安装后跑一遍)

```bash
sudo systemctl is-active kamailio rtpengine-daemon caddy
sudo systemctl is-enabled kamailio rtpengine-daemon caddy
sudo lsmod | grep xt_RTPENGINE
sudo ss -lnup | grep -E ':15060|:2223'
sudo ss -lntp | grep -E ':80|:443|:15062'
```

重启宿主机后再跑一遍,所有服务应自动起来。
```

- [ ] **Step 3: 提交**

```bash
git add install/install.env.example install/README.md
git commit -m "docs: add install/ README and env example"
```

---

## Task 11: 端到端 smoke checklist(人工真机验收)

**Files:**
- Create: `docs/superpowers/checklists/sbc-install-smoke.md`

**目标:** 因为真包安装无法在 CI 跑,把验收步骤固化成 checklist 让人在真机执行。

- [ ] **Step 1: 写 checklist**

```markdown
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
```

- [ ] **Step 2: 提交**

```bash
git add docs/superpowers/checklists/sbc-install-smoke.md
git commit -m "docs: add real-machine smoke checklist"
```

---

## 自审记录

按 writing-plans 要求做了下面四项自审:

1. **Spec coverage:**
   - §2 仓库布局 → Task 1
   - §3 调用约定(位置参数 + whiptail 菜单 + 未知服务报错 + 非交互拦截)→ Task 5
   - §4 必填变量 → Task 10(env.example) + 各服务模块的 require_vars
   - §5 严格失败 → install.sh 的 `set -euo pipefail` + trap(Task 5)
   - §6.1 前置检查 → Task 2(OS)+ 各服务模块的 _check_vars / _check_iface
   - §6.2–6.4b apt 源 → 各服务模块的 _<svc>_add_repo
   - §6.5 安装包 → 各服务模块的 _<svc>_install_pkgs
   - §6.6 内核模块 → Task 7 _rtpe_load_kernel_mod
   - §6.7 渲染配置(含 RUN_KAMAILIO 修复)→ Task 4(render_tpl) + 各服务的 _render
   - §6.8 drop-in → 各服务的 _install_dropin
   - §6.9 enable --now + is-active 校验 → 各服务的 do_install 末段
   - §6.10 健康摘要 → 各服务的 do_health
   - §7 reconfigure → 各服务的 do_reconfigure
   - §8 systemd drop-in 内容 → Task 6/7/8 各自的 override.conf
   - §11 失败点对策 → 由 require_vars / _check_iface / madison 探测 / lsmod 校验落实
   - §12 验收 → Task 11 smoke checklist

2. **Placeholder scan:** 无 TBD / 未填实现。

3. **Type consistency:** 函数命名一致(`do_install` / `do_reconfigure` / `do_health` + `_<svc>_<step>` 私有函数);变量命名与 spec §4 一致;`UBUNTU_CODENAME` 由 install.sh 主入口 export,各服务模块假定它已存在并加入 require_vars。

4. **Ambiguity:** 主入口与服务模块之间用 `INSTALL_SERVICES_DIR` 注入测试存根、`SKIP_ROOT_CHECK`/`SKIP_OS_CHECK` 提供测试旁路,接口边界明确。
