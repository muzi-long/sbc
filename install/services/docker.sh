#!/usr/bin/env bash
# install/services/docker.sh
# 暴露 do_install / do_reconfigure / do_health,被 install.sh 在子 shell 中 source。
# 依赖:已 source common.sh。目标 OS:Debian 12 (bookworm)。
# docker 没有必填环境变量,所有调整由运维自行编辑 /etc/docker/daemon.json。

_docker_install_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

_docker_check_vars() {
  # docker 不需要任何必填环境变量,空 require_vars(留这个函数保持接口同形)
  true
}

# 卸载可能冲突的旧版 docker(Debian 自带的 docker.io、上游 docker-engine 等)
# 这些包可能根本没装,所以失败也忽略
_docker_purge_old() {
  apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true
}

# 配 Docker 官方 apt 源(Debian 12 bookworm)
_docker_add_repo() {
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --batch --no-tty --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  # codename 硬编码 bookworm,与项目目标 OS 对齐
  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable
EOF
  apt-get update -o Dir::Etc::sourcelist="sources.list.d/docker.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
}

_docker_install_pkgs() {
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
}

do_install() {
  _docker_check_vars
  _docker_purge_old
  _docker_add_repo
  _docker_install_pkgs
  systemctl enable docker
  # apt 装 docker-ce 时 postinst 已 start;此处显式 restart 保持模块同形约定
  systemctl restart docker
  wait_for_active docker 15 || {
    journalctl -u docker -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_reconfigure() {
  _docker_check_vars
  # docker 没有由本脚本管理的配置文件(daemon.json 由运维手编)
  # reconfigure 仅 restart 服务,让运维改 daemon.json 后能用 reconfigure 生效
  systemctl restart docker
  wait_for_active docker 15 || {
    journalctl -u docker -n 50 --no-pager >&2
    return 1
  }
  do_health
}

do_health() {
  echo "--- docker ---"
  docker version --format 'client: {{.Client.Version}}, server: {{.Server.Version}}' 2>/dev/null || true
  systemctl is-active docker
  systemctl is-enabled docker
  # docker compose v2 子命令是否可用
  docker compose version 2>/dev/null | head -1 || echo "(docker compose v2 不可用)"
}
