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
  rm -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --batch --no-tty --yes --dearmor -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  chmod 0644 /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -o Dir::Etc::sourcelist="sources.list.d/caddy-stable.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
}

# 渲染 Caddyfile 到 /etc/caddy/,事务性:先渲染到 .new 文件,fmt + validate 通过后才原子替换。
# 要求 caddy 用户已存在(由 apt install caddy 创建)。
_caddy_render() {
  local install_dir dst="/etc/caddy/Caddyfile" tmp="/etc/caddy/Caddyfile.new"
  install_dir="$(_caddy_install_dir)"
  install -d -m 0755 /etc/caddy
  render_tpl "$install_dir/conf/caddy/Caddyfile.tpl" "$tmp" \
    "CADDY_API_DOMAIN=$CADDY_API_DOMAIN" \
    "CADDY_API_UPSTREAM=$CADDY_API_UPSTREAM" \
    "CADDY_APP_DOMAIN=$CADDY_APP_DOMAIN" \
    "CADDY_APP_UPSTREAM=$CADDY_APP_UPSTREAM" \
    "CADDY_WEBRTC_DOMAIN=$CADDY_WEBRTC_DOMAIN" \
    "CADDY_WEBRTC_UPSTREAM=$CADDY_WEBRTC_UPSTREAM"
  caddy fmt --overwrite "$tmp"
  if ! caddy validate --config "$tmp"; then
    echo "ERROR: 新 Caddyfile 校验失败,保留原配置" >&2
    rm -f "$tmp"
    return 1
  fi
  # 原子替换 + 设置 owner/mode
  install -m 644 -o caddy -g caddy "$tmp" "$dst"
  rm -f "$tmp"
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
  wait_for_active caddy 15 || {
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
  wait_for_active caddy 15 || {
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
