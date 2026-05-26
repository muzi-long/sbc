#!/usr/bin/env bash
# install/lib/common.sh
# 共享工具函数。所有 shell 函数都用 `(... )` 子 shell 形式以隔离副作用,
# 或在文档中显式说明会修改的全局变量。

set -o pipefail

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
