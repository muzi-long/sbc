#!/usr/bin/env bash
# install/services/caddy.sh
# 暴露 do_install / do_reconfigure / do_health,被 install.sh 在子 shell 中 source。
# 依赖:已 source common.sh、UBUNTU_CODENAME 已导出。

# ===== 必填变量(由调用 install.sh 的环境注入,例如 source install.env)=====
# 用 `: "${X:=}"` 保护:若未注入,先设为空字符串,避免 set -u 报 unbound variable,
# 后续 require_vars 会把空字符串识别为 missing 并报错列出。
: "${CADDY_API_DOMAIN:=}"
: "${CADDY_API_UPSTREAM:=}"
: "${CADDY_APP_DOMAIN:=}"
: "${CADDY_APP_UPSTREAM:=}"
: "${CADDY_WEBRTC_DOMAIN:=}"
: "${CADDY_WEBRTC_UPSTREAM:=}"

# 返回 install/ 目录的绝对路径(本仓库 install/ 子目录,内含 conf/、systemd/、services/ 等)
_caddy_install_dir() {
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

# 渲染 Caddyfile 到 /etc/caddy/,要求 caddy 用户已存在(由 apt install caddy 创建)
_caddy_render() {
  local install_dir dst="/etc/caddy/Caddyfile"
  install_dir="$(_caddy_install_dir)"
  install -d -m 0755 /etc/caddy
  render_tpl "$install_dir/conf/caddy/Caddyfile.tpl" "$dst" \
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
  local install_dir
  install_dir="$(_caddy_install_dir)"
  install -d -m 0755 /etc/systemd/system/caddy.service.d
  install -m 0644 "$install_dir/systemd/caddy.service.d/override.conf" \
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
  sleep 3  # 等待 caddy 完成初始化
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
  sleep 2  # 等待 caddy reload 完成
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
