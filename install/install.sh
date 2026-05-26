#!/usr/bin/env bash
# install/install.sh — 主入口
set -euo pipefail
trap 'code=$?; case $code in 1|2) ;; *) echo "[FAIL] line $LINENO (exit=$code)" >&2 ;; esac' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
SERVICES_DIR="${INSTALL_SERVICES_DIR:-$SCRIPT_DIR/services}"

# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"

KNOWN_SERVICES=(kamailio rtpengine caddy freeswitch)

usage() {
  cat <<EOF
用法: $0 <install|reconfigure> [service ...]

已知服务: ${KNOWN_SERVICES[*]}

不传服务名时弹出多选菜单(需要交互终端)。
非交互终端必须显式列出服务名。
EOF
}

ensure_prereqs() {
  # 入参:剩余的服务名列表(可能为空,表示交互式)
  # 全部服务都需要的基础工具
  local needed=(gnupg ca-certificates curl wget whiptail)
  local s want_rtpe=0 want_fs=0
  if [ "$#" -eq 0 ]; then
    want_rtpe=1  # 交互式,可能选 rtpengine
    want_fs=1    # 交互式,可能选 freeswitch
  else
    for s in "$@"; do
      [ "$s" = "rtpengine" ] && want_rtpe=1
      [ "$s" = "freeswitch" ] && want_fs=1
    done
  fi
  if [ "$want_rtpe" -eq 1 ]; then
    needed+=(dkms "linux-headers-$(uname -r)")
  fi
  if [ "$want_fs" -eq 1 ]; then
    needed+=(git cmake build-essential autoconf automake libtool libtool-bin pkg-config lsb-release uuid-dev libssl-dev yasm nasm)
  fi
  apt-get update -qq
  apt-get install -y "${needed[@]}"
}

is_known_service() {
  local s="$1"
  for k in "${KNOWN_SERVICES[@]}"; do
    [ "$s" = "$k" ] && return 0
  done
  return 1
}

pick_services_via_menu() {
  # 输出选中的服务名,空格分隔。
  # 注意:本函数被 do_dispatch 用 $(...) 调用,所以 fd 1 必然是管道,
  # 只检查 stdin(fd 0)是否为终端 —— 用户的键盘输入靠它。
  if [ ! -t 0 ]; then
    echo "ERROR: 非交互终端下必须显式列出服务名(non-interactive)" >&2
    return 1
  fi
  if ! command -v whiptail >/dev/null 2>&1; then
    # 正常路径下 ensure_prereqs 已装好 whiptail;这里是兜底
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
    IFS=' ' read -r -a services <<< "$picked"
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
    detect_debian_bookworm
  fi

  # 全局前置:确保基础工具就位(干净 Debian 12 默认不带 curl/wget/whiptail)
  if [ "${SKIP_PREREQ:-0}" != "1" ]; then
    ensure_prereqs "$@"
  fi

  do_dispatch "$action" "$@"
}

main "$@"
