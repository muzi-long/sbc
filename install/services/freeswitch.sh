#!/usr/bin/env bash
# install/services/freeswitch.sh
# 暴露 do_install / do_reconfigure / do_health,被 install.sh 在子 shell 中 source。
# 依赖:已 source common.sh。目标 OS:Debian 12 (bookworm)。

# ===== 可选变量(由调用 install.sh 的环境注入,例如 source install.env)=====
# freeswitch 不需要必填变量,所有业务定制走 /usr/local/freeswitch/conf/ 手改
: "${FS_BUILD_DIR:=/usr/local/src}"
: "${FS_VERSION:=v1.10.12}"
: "${FS_PREFIX:=/usr/local/freeswitch}"

# 返回 install/ 目录的绝对路径
_fs_install_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

_fs_check_vars() {
  # FS 没有必填变量,只检查编译/安装路径变量
  require_vars FS_BUILD_DIR FS_VERSION FS_PREFIX
}

# 装编译依赖
_fs_install_deps() {
  apt-get install -y \
    git cmake build-essential autoconf automake libtool libtool-bin \
    pkg-config gnupg wget lsb-release uuid-dev libssl-dev \
    yasm nasm \
    libsqlite3-dev libcurl4-openssl-dev libpcre3-dev libspeex-dev libspeexdsp-dev \
    libldns-dev libedit-dev libtiff-dev libjpeg-dev libpng-dev libsndfile1-dev \
    libopus-dev libvorbis-dev libogg-dev libflac-dev libavformat-dev libswscale-dev \
    libavresample-dev libavutil-dev libavcodec-dev libx11-dev \
    libfftw3-dev libpcap-dev libxml2-dev libuv1-dev libfltk1.3-dev sox netpbm
}

# 源码编译(幂等:freeswitch 二进制已存在则跳过)
_fs_build_from_source() {
  if [ -x "$FS_PREFIX/bin/freeswitch" ]; then
    echo "[freeswitch] $FS_PREFIX/bin/freeswitch 已存在,跳过编译(若要重编,先删除该文件)" >&2
    return 0
  fi
  install -d -m 0755 "$FS_BUILD_DIR"

  # spandsp(fs 分支)
  if [ ! -d "$FS_BUILD_DIR/spandsp" ]; then
    git clone -b fs https://github.com/freeswitch/spandsp.git "$FS_BUILD_DIR/spandsp"
  fi
  ( cd "$FS_BUILD_DIR/spandsp" && ./bootstrap.sh -j && ./configure && make && make install )

  # sofia-sip(master 分支)
  if [ ! -d "$FS_BUILD_DIR/sofia-sip" ]; then
    git clone https://github.com/freeswitch/sofia-sip.git "$FS_BUILD_DIR/sofia-sip"
  fi
  ( cd "$FS_BUILD_DIR/sofia-sip" && ./bootstrap.sh -j && ./configure && make && make install )

  # libks v1.8.3
  if [ ! -d "$FS_BUILD_DIR/libks" ]; then
    git clone -b v1.8.3 https://github.com/signalwire/libks.git "$FS_BUILD_DIR/libks"
  fi
  ( cd "$FS_BUILD_DIR/libks" && cmake . && make && make install && ldconfig )

  # signalwire-c v1.3.3
  if [ ! -d "$FS_BUILD_DIR/signalwire-c" ]; then
    git clone -b v1.3.3 https://github.com/signalwire/signalwire-c.git "$FS_BUILD_DIR/signalwire-c"
  fi
  ( cd "$FS_BUILD_DIR/signalwire-c" && cmake . && make && make install && ldconfig )

  # freeswitch 主体 v1.10.12
  if [ ! -d "$FS_BUILD_DIR/freeswitch" ]; then
    git clone -b "$FS_VERSION" https://github.com/signalwire/freeswitch.git "$FS_BUILD_DIR/freeswitch"
  fi
  (
    cd "$FS_BUILD_DIR/freeswitch"
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:${PKG_CONFIG_PATH:-}
    ldconfig
    ./bootstrap.sh
    # 禁掉 mod_skinny(参考 Dockerfile 同样的处理)
    sed -i 's/endpoints\/mod_skinny/#endpoints\/mod_skinny/' modules.conf
    ./configure
    make
    make install
    make cd-sounds-install
    make cd-moh-install
  )

  # 软链
  ln -sf "$FS_PREFIX/bin/freeswitch" /usr/bin/freeswitch
  ln -sf "$FS_PREFIX/bin/fs_cli" /usr/bin/fs_cli

  # mod_xml_curl
  ( cd "$FS_BUILD_DIR/freeswitch/src/mod/xml_int/mod_xml_curl" && make install )
}

# 首次落地 conf 目录,不覆盖运维已修改的文件
# 用 cp -rn:目录拷过去,已存在文件不覆盖(等同 dispatcher.list 策略)
_fs_install_conf() {
  local install_dir
  install_dir="$(_fs_install_dir)"
  install -d -m 0755 "$FS_PREFIX/conf"
  if [ -z "$(ls -A "$FS_PREFIX/conf" 2>/dev/null)" ]; then
    cp -r "$install_dir/conf/freeswitch/conf/." "$FS_PREFIX/conf/"
    echo "[freeswitch] 已落地参考 conf 到 $FS_PREFIX/conf/(首次安装)" >&2
  else
    echo "[freeswitch] $FS_PREFIX/conf/ 已存在内容,不覆盖(reconfigure 同样不动 conf)" >&2
  fi

  install -d -m 0755 /data/recordings
  install -d -m 0755 /data/audios
}

# 装 systemd unit(完整 unit,不是 drop-in)
_fs_install_unit() {
  local install_dir
  install_dir="$(_fs_install_dir)"
  install -m 0644 "$install_dir/systemd/freeswitch.service" /etc/systemd/system/freeswitch.service
  systemctl daemon-reload
}

do_install() {
  _fs_check_vars
  _fs_install_deps
  _fs_build_from_source
  _fs_install_conf
  _fs_install_unit
  systemctl enable --now freeswitch
  # freeswitch 启动较慢(加载几十个模块),timeout 60s
  wait_for_active freeswitch 60 || {
    journalctl -u freeswitch -n 100 --no-pager >&2
    return 1
  }
  do_health
}

do_reconfigure() {
  _fs_check_vars
  # 不动 conf,只 restart
  systemctl restart freeswitch
  wait_for_active freeswitch 60 || {
    journalctl -u freeswitch -n 100 --no-pager >&2
    return 1
  }
  do_health
}

do_health() {
  echo "--- freeswitch ---"
  freeswitch -version 2>/dev/null | head -1 || true
  systemctl is-active freeswitch
  systemctl is-enabled freeswitch
  # 5060 是 FS 默认 SIP 端口(internal/external profile)
  ss -lnup 2>/dev/null | grep ':5060\|:5080' || echo "(FS SIP 端口 5060/5080 未在监听)"
  # ESL
  ss -lntp 2>/dev/null | grep ':8021' || echo "(ESL 8021 未在监听)"
}
