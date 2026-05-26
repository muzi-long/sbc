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
# 残留即非零退出。值中可含 / & 等特殊字符(awk 字符串替换,非 sed)。
render_tpl() {
  local src="$1" dst="$2"
  shift 2
  if [ ! -r "$src" ]; then
    echo "ERROR: 模板不存在: $src" >&2
    return 1
  fi
  # 拼出 awk 程序:每个 kv 一条 gsub
  # BEGIN 块中转义替换变量里的 \ 和 &,避免 gsub 把 & 解释为"匹配串"
  local awk_begin='BEGIN{'
  local awk_body='{ line=$0;'
  local kv key val awk_args=()
  local i=0
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    awk_args+=(-v "v${i}=$val")
    awk_begin+=" gsub(/[\\\\&]/, \"\\\\\\\\&\", v${i});"
    awk_body+=" gsub(/__${key}__/, v${i}, line);"
    i=$((i+1))
  done
  awk_begin+='}'
  awk_body+=' print line; }'
  awk "${awk_args[@]}" "${awk_begin} ${awk_body}" "$src" > "$dst"

  local leftover
  leftover="$(grep -oE '__[A-Z][A-Z0-9_]*__' "$dst" | sort -u || true)"
  if [ -n "$leftover" ]; then
    echo "ERROR: 渲染后残留占位符:" >&2
    echo "$leftover" >&2
    return 1
  fi
}
