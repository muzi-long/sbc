#!/usr/bin/env bash
# install/services/kamailio.sh
# 暴露 do_install / do_reconfigure / do_health,被 install.sh 在子 shell 中 source。
# 依赖:已 source common.sh、UBUNTU_CODENAME 已导出。

# ===== 必填变量(由调用 install.sh 的环境注入,例如 source install.env)=====
# 用 `: "${X:=}"` 保护:若未注入,先设为空字符串,避免 set -u 报 unbound variable,
# 后续 require_vars 会把空字符串识别为 missing 并报错列出。
: "${PUBLIC_IP:=}"
: "${PRIVATE_IP:=}"
: "${LISTEN_IFACE:=eth0}"
: "${SIP_UDP_PORT:=15060}"
: "${SIP_TCP_PORT:=15062}"
: "${KAM_ALIAS_1:=}"
: "${KAM_ALIAS_2:=}"
: "${DB_HOST:=}"
: "${DB_PORT:=3306}"
: "${DB_USER:=}"
: "${DB_PASS:=}"
: "${DB_NAME:=}"
: "${REDIS_HOST:=}"
: "${REDIS_PORT:=6379}"
: "${REDIS_PASS:=}"
: "${RTPE_NG_PORT:=2223}"
: "${KAMAILIO_BRANCH:=58}"

# 返回 install/ 目录的绝对路径
_kam_install_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

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
  # 默认 disable 的坑:Ubuntu 包默认 /etc/default/kamailio 里 RUN_KAMAILIO=no
  sed -i 's/^#*RUN_KAMAILIO=.*/RUN_KAMAILIO=yes/' /etc/default/kamailio
  grep -q '^RUN_KAMAILIO=yes' /etc/default/kamailio || \
    echo 'RUN_KAMAILIO=yes' >> /etc/default/kamailio
}

# 渲染 kamailio.cfg + lua/dispatcher.list 到 /etc/kamailio/,
# 要求 kamailio 用户已存在(由 apt install kamailio 创建)
_kam_render() {
  local install_dir
  install_dir="$(_kam_install_dir)"
  install -d -m 0755 /etc/kamailio
  render_tpl "$install_dir/conf/kamailio/kamailio.cfg.tpl" /etc/kamailio/kamailio.cfg \
    "PUBLIC_IP=$PUBLIC_IP" "LISTEN_IFACE=$LISTEN_IFACE" \
    "SIP_UDP_PORT=$SIP_UDP_PORT" "SIP_TCP_PORT=$SIP_TCP_PORT" \
    "KAM_ALIAS_1=$KAM_ALIAS_1" "KAM_ALIAS_2=$KAM_ALIAS_2" \
    "DB_HOST=$DB_HOST" "DB_PORT=$DB_PORT" "DB_USER=$DB_USER" "DB_PASS=$DB_PASS" "DB_NAME=$DB_NAME" \
    "REDIS_HOST=$REDIS_HOST" "REDIS_PORT=$REDIS_PORT" "REDIS_PASS=$REDIS_PASS" \
    "RTPE_NG_PORT=$RTPE_NG_PORT"
  install -m 0644 -o kamailio -g kamailio "$install_dir/conf/kamailio/kamailio.lua" /etc/kamailio/kamailio.lua
  install -m 0644 -o kamailio -g kamailio "$install_dir/conf/kamailio/dispatcher.list" /etc/kamailio/dispatcher.list
  chown kamailio:kamailio /etc/kamailio/kamailio.cfg
  chmod 640 /etc/kamailio/kamailio.cfg  # 含 DB 密码,严格保护
}

_kam_install_dropin() {
  local install_dir
  install_dir="$(_kam_install_dir)"
  install -d -m 0755 /etc/systemd/system/kamailio.service.d
  install -m 0644 "$install_dir/systemd/kamailio.service.d/override.conf" \
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
  sleep 3  # 等待 kamailio 完成初始化
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
  sleep 2  # 等待 kamailio reload 完成
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
