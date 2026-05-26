#!/usr/bin/env bash
# install/lib/common.sh
# 共享工具函数。所有 shell 函数都用 `(... )` 子 shell 形式以隔离副作用,
# 或在文档中显式说明会修改的全局变量。

require_root() {
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

# render_tpl SRC DST KEY=VAL [KEY=VAL ...]
# 把 SRC 中所有 __KEY__ 替换为 VAL,写到 DST。完成后扫描残留占位符,
# 残留即非零退出。值中可含 / & \ 等任意字符(通过 ENVIRON 传值,不经 awk -v 的 C 风格转义)。
render_tpl() {
  local src="$1" dst="$2"
  shift 2
  if [ ! -r "$src" ]; then
    echo "ERROR: 模板不存在: $src" >&2
    return 1
  fi

  # 把 KEY=VAL 列表 export 为 v0/v1/...,让 awk 通过 ENVIRON 数组读
  # (awk -v 会对反斜杠做 C 风格转义展开,无法承载 DB_PASS 含 \ 等场景)
  local kv key val i=0
  local -a keys=()
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    export "v${i}=$val"
    keys+=("$key")
    i=$((i+1))
  done

  # 拼 awk 程序:
  # BEGIN 块从 ENVIRON 取出每个 v0/v1/...
  # 主循环对每行用 index()+substr() 循环替换 __KEY__,避免 gsub 替换串
  # 中 & 和 \ 的元字符语义(跨 BSD awk/gawk/mawk 均安全)。
  local awk_begin='BEGIN{'
  local awk_body='{ line=$0;'
  local n=$i
  i=0
  while [ "$i" -lt "$n" ]; do
    awk_begin+=" v${i}=ENVIRON[\"v${i}\"]; k${i}=\"__${keys[$i]}__\"; kl${i}=length(k${i});"
    awk_body+=" { r=\"\"; t=line; while((p=index(t,k${i}))>0){r=r substr(t,1,p-1) v${i}; t=substr(t,p+kl${i})}; line=r t; }"
    i=$((i+1))
  done
  awk_begin+='}'
  awk_body+=' print line; }'

  if ! awk "${awk_begin} ${awk_body}" "$src" > "$dst"; then
    echo "ERROR: awk 渲染失败" >&2
    return 1
  fi

  # 清理临时 export(不污染调用方)
  i=0
  while [ "$i" -lt "$n" ]; do
    unset "v${i}"
    i=$((i+1))
  done

  local leftover
  leftover="$(grep -oE '__[A-Z][A-Z0-9_]*__' "$dst" | sort -u || true)"
  if [ -n "$leftover" ]; then
    echo "ERROR: 渲染后残留占位符:" >&2
    echo "$leftover" >&2
    return 1
  fi
}

# wait_for_active UNIT [TIMEOUT_SECONDS]
# 轮询 systemctl is-active,超时返回非零
# 默认 timeout 15 秒
wait_for_active() {
  local unit="$1"
  local timeout="${2:-15}"
  local i=0
  while [ "$i" -lt "$timeout" ]; do
    if systemctl is-active "$unit" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  return 1
}
