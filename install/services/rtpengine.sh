#!/usr/bin/env bash
# install/services/rtpengine.sh
# 暴露 do_install / do_reconfigure / do_health,被 install.sh 在子 shell 中 source。
# 依赖:已 source common.sh。目标 OS:Debian 12 (bookworm)。

# ===== 必填变量(由调用 install.sh 的环境注入,例如 source install.env)=====
# 用 `: "${X:=}"` 保护:若未注入,先设为空字符串,避免 set -u 报 unbound variable,
# 后续 require_vars 会把空字符串识别为 missing 并报错列出。
: "${PUBLIC_IP:=}"
: "${PRIVATE_IP:=}"
: "${RTPE_NG_PORT:=2223}"
: "${RTPE_PORT_MIN:=40000}"
: "${RTPE_PORT_MAX:=60000}"
: "${RTPENGINE_RELEASE:=mr12.5.1}"

# 返回 install/ 目录的绝对路径
_rtpe_install_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

_rtpe_check_vars() {
  require_vars PUBLIC_IP PRIVATE_IP RTPE_NG_PORT RTPE_PORT_MIN RTPE_PORT_MAX RTPENGINE_RELEASE
}

_rtpe_add_repo() {
  install -d -m 0755 /etc/apt/keyrings
  rm -f /etc/apt/keyrings/sipwise.gpg
  wget -qO- 'https://deb.sipwise.com/spce/keyring/sipwise-keyring-bootstrap.gpg' \
    | gpg --batch --no-tty --yes --dearmor -o /etc/apt/keyrings/sipwise.gpg
  chmod 0644 /etc/apt/keyrings/sipwise.gpg
  # sipwise spce/mr12.5.1 只发布 Debian 12 (bookworm) 仓库,与目标 OS 天然对齐。
  cat > /etc/apt/sources.list.d/sipwise.list <<EOF
deb [signed-by=/etc/apt/keyrings/sipwise.gpg] https://deb.sipwise.com/spce/${RTPENGINE_RELEASE}/ bookworm main
EOF
  apt-get update -o Dir::Etc::sourcelist="sources.list.d/sipwise.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
  if ! apt-cache madison ngcp-rtpengine | grep -q .; then
    echo "ERROR: sipwise 仓库 (release=${RTPENGINE_RELEASE}, bookworm) 没有 ngcp-rtpengine 包" >&2
    return 1
  fi
}

_rtpe_install_pkgs() {
  apt-get install -y dkms "linux-headers-$(uname -r)"
  apt-get install -y ngcp-rtpengine ngcp-rtpengine-kernel-dkms
}

_rtpe_load_kernel_mod() {
  if ! modprobe xt_RTPENGINE 2>&1; then
    echo "ERROR: 加载 xt_RTPENGINE 失败,检查 DKMS 状态:" >&2
    dkms status 2>/dev/null | grep -i rtpengine >&2 || echo "(dkms 未显示 rtpengine 条目,headers 不匹配?)" >&2
    return 1
  fi
  echo "xt_RTPENGINE" > /etc/modules-load.d/rtpengine.conf
  lsmod | grep -q xt_RTPENGINE || {
    echo "ERROR: xt_RTPENGINE 未加载" >&2
    return 1
  }
}

# 渲染 rtpengine.conf 到 /etc/rtpengine/,要求 rtpengine 用户已存在(由 apt install ngcp-rtpengine 创建)
_rtpe_render() {
  local install_dir dst="/etc/rtpengine/rtpengine.conf"
  install_dir="$(_rtpe_install_dir)"
  install -d -m 0755 /etc/rtpengine
  render_tpl "$install_dir/conf/rtpengine/rtpengine.conf.tpl" "$dst" \
    "PRIVATE_IP=$PRIVATE_IP" \
    "PUBLIC_IP=$PUBLIC_IP" \
    "RTPE_NG_PORT=$RTPE_NG_PORT" \
    "RTPE_PORT_MIN=$RTPE_PORT_MIN" \
    "RTPE_PORT_MAX=$RTPE_PORT_MAX"
  chown rtpengine:rtpengine "$dst"
  chmod 640 "$dst"  # 640:rtpengine 组只读,虽然本配置不含密钥,但与 kamailio 保持一致
}

_rtpe_install_dropin() {
  local install_dir
  install_dir="$(_rtpe_install_dir)"
  install -d -m 0755 /etc/systemd/system/ngcp-rtpengine-daemon.service.d
  install -m 0644 "$install_dir/systemd/ngcp-rtpengine-daemon.service.d/override.conf" \
    /etc/systemd/system/ngcp-rtpengine-daemon.service.d/override.conf
  systemctl daemon-reload
}

do_install() {
  _rtpe_check_vars
  _rtpe_add_repo
  _rtpe_install_pkgs
  _rtpe_load_kernel_mod
  _rtpe_render
  _rtpe_install_dropin
  systemctl enable --now ngcp-rtpengine-daemon
  wait_for_active ngcp-rtpengine-daemon 15 || {
    lsmod | grep xt_RTPENGINE >&2 || echo "(hint: xt_RTPENGINE 内核模块未加载,可能 DKMS 编译失败)" >&2
    journalctl -u ngcp-rtpengine-daemon -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_reconfigure() {
  _rtpe_check_vars
  _rtpe_render
  _rtpe_install_dropin
  systemctl restart ngcp-rtpengine-daemon
  wait_for_active ngcp-rtpengine-daemon 15 || {
    lsmod | grep xt_RTPENGINE >&2 || echo "(hint: xt_RTPENGINE 内核模块未加载,可能 DKMS 编译失败)" >&2
    journalctl -u ngcp-rtpengine-daemon -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_health() {
  echo "--- rtpengine ---"
  rtpengine --version 2>/dev/null | head -1 || true
  lsmod | grep xt_RTPENGINE || echo "(xt_RTPENGINE 未加载)"
  systemctl is-active ngcp-rtpengine-daemon
  systemctl is-enabled ngcp-rtpengine-daemon
  ss -lnup 2>/dev/null | grep ":${RTPE_NG_PORT}" || echo "(NG 端口 ${RTPE_NG_PORT} 未在监听)"
}
