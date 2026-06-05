#!/usr/bin/env bash
# install/services/freeswitch.sh
# 暴露 do_install / do_reconfigure / do_health,被 install.sh 在子 shell 中 source。
# 依赖:已 source common.sh。目标 OS:Debian 12 (bookworm)。

# ===== 可选变量(由调用 install.sh 的环境注入,例如 source install.env)=====
# freeswitch 不需要必填变量,所有业务定制走 /usr/local/freeswitch/conf/ 手改
: "${FS_BUILD_DIR:=/usr/local/src}"
: "${FS_VERSION:=v1.10.12}"
: "${FS_PREFIX:=/usr/local/freeswitch}"
# GitHub 代理前缀,加速国内访问。空 = 直连。
# 推荐 GH_PROXY="https://gh-proxy.com/" (实测 ~6 MB/s,直连 ~17 KB/s)
# 末尾必须带斜杠;用法:${GH_PROXY}https://github.com/...
: "${GH_PROXY:=}"

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
    libswresample-dev libavutil-dev libavcodec-dev libavfilter-dev libx11-dev \
    libfftw3-dev libpcap-dev libxml2-dev libuv1-dev libfltk1.3-dev sox netpbm \
    liblua5.2-dev libpq-dev
}

# 带重试的 git clone:GitHub 在国内访问偶发 GnuTLS / TLS 断连,重试 5 次
# 用法:_fs_git_clone_retry DST_DIR URL [BRANCH]
# 注意:不用 --depth 1,因为 libks 等仓库的 CMakeLists.txt 会读 git tag
# 历史生成 changelog,shallow clone 会让 cmake 拿不到 v1.8.3^ 报错。
_fs_git_clone_retry() {
  local dst="$1" url="$2" branch="${3:-}"
  local n=0 max=5
  if [ -d "$dst/.git" ]; then
    return 0
  fi
  # 清掉之前可能的半成品目录
  rm -rf "$dst"
  while [ "$n" -lt "$max" ]; do
    n=$((n+1))
    if [ -n "$branch" ]; then
      git clone -b "$branch" "$url" "$dst" && return 0
    else
      git clone "$url" "$dst" && return 0
    fi
    echo "[freeswitch] git clone $url 失败(第 $n/$max 次),5 秒后重试..." >&2
    rm -rf "$dst"
    sleep 5
  done
  echo "ERROR: git clone $url 重试 $max 次仍失败" >&2
  return 1
}

# 带重试的 tarball 下载并解压(GitHub release/archive 比 git clone 快 5-10 倍,
# 国内访问 freeswitch 主仓库 ~700MB 的 git history 极慢且容易挂)。
# 用法:_fs_tarball_fetch_retry DST_DIR URL TOPDIR
# DST_DIR:最终源码目录;URL:tarball 地址;TOPDIR:tarball 解压后的顶层目录名
_fs_tarball_fetch_retry() {
  local dst="$1" url="$2" topdir="$3"
  local n=0 max=5
  if [ -d "$dst" ] && [ "$(ls -A "$dst" 2>/dev/null)" ]; then
    return 0
  fi
  rm -rf "$dst"
  local tmpdir
  tmpdir="$(mktemp -d)"
  while [ "$n" -lt "$max" ]; do
    n=$((n+1))
    if wget --timeout=60 --tries=1 -qO "$tmpdir/src.tar.gz" "$url"; then
      if tar -xzf "$tmpdir/src.tar.gz" -C "$tmpdir"; then
        if [ -d "$tmpdir/$topdir" ]; then
          mv "$tmpdir/$topdir" "$dst"
          rm -rf "$tmpdir"
          return 0
        fi
        echo "[freeswitch] tarball 解压后未找到 $topdir,实际:$(ls "$tmpdir")" >&2
      fi
    fi
    echo "[freeswitch] 下载 $url 失败(第 $n/$max 次),5 秒后重试..." >&2
    rm -f "$tmpdir/src.tar.gz"
    sleep 5
  done
  rm -rf "$tmpdir"
  echo "ERROR: 下载 $url 重试 $max 次仍失败" >&2
  return 1
}

# 源码编译(幂等:freeswitch 二进制已存在则跳过)
_fs_build_from_source() {
  if [ -x "$FS_PREFIX/bin/freeswitch" ]; then
    echo "[freeswitch] $FS_PREFIX/bin/freeswitch 已存在,跳过编译(若要重编,先删除该文件)" >&2
    return 0
  fi
  install -d -m 0755 "$FS_BUILD_DIR"

  # 提高 git http 缓冲、关闭 smart-http 压缩(国内访问 GitHub 大仓库更稳)
  git config --global http.postBuffer 524288000 || true
  git config --global http.lowSpeedLimit 1000 || true
  git config --global http.lowSpeedTime 60 || true

  # spandsp(fs 分支)
  _fs_git_clone_retry "$FS_BUILD_DIR/spandsp" "${GH_PROXY}https://github.com/freeswitch/spandsp.git" fs
  ( cd "$FS_BUILD_DIR/spandsp" && ./bootstrap.sh -j && ./configure && make && make install )

  # sofia-sip(master 分支)
  _fs_git_clone_retry "$FS_BUILD_DIR/sofia-sip" "${GH_PROXY}https://github.com/freeswitch/sofia-sip.git"
  ( cd "$FS_BUILD_DIR/sofia-sip" && ./bootstrap.sh -j && ./configure && make && make install )

  # libks v1.8.3
  _fs_git_clone_retry "$FS_BUILD_DIR/libks" "${GH_PROXY}https://github.com/signalwire/libks.git" v1.8.3
  ( cd "$FS_BUILD_DIR/libks" && cmake . && make && make install && ldconfig )

  # signalwire-c v1.3.3
  _fs_git_clone_retry "$FS_BUILD_DIR/signalwire-c" "${GH_PROXY}https://github.com/signalwire/signalwire-c.git" v1.3.3
  ( cd "$FS_BUILD_DIR/signalwire-c" && cmake . && make && make install && ldconfig )

  # freeswitch 主体 v1.10.12 — 用 tarball 下载(git clone ~700MB 在国内极慢易挂,
  # tarball ~80MB,快 5-10 倍)。FreeSWITCH 主体的 bootstrap.sh 不依赖 git 历史。
  # 注意:tag 形如 v1.10.12,GitHub archive 解压后顶层目录是 freeswitch-1.10.12(去 v)
  # 若设了 GH_PROXY,加速下载(国内推荐 https://gh-proxy.com/)
  local fs_tag_no_v="${FS_VERSION#v}"
  _fs_tarball_fetch_retry "$FS_BUILD_DIR/freeswitch" \
    "${GH_PROXY}https://github.com/signalwire/freeswitch/archive/refs/tags/${FS_VERSION}.tar.gz" \
    "freeswitch-${fs_tag_no_v}"
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
  )
  # 不跑 make cd-sounds-install / cd-moh-install:files.freeswitch.org 国内
  # 龟速 + 8 个包共 ~670MB,曾让编译拖到数小时还失败。改用仓库自带的
  # music-8000 tarball,SBC 场景够用(do_install 顶层调用)。

  # mod_xml_curl(主体编译完后才能编)
  ( cd "$FS_BUILD_DIR/freeswitch/src/mod/xml_int/mod_xml_curl" && make install )
}

# 解压仓库自带的 sounds tarball 到 $FS_PREFIX/sounds/。
# 上游 files.freeswitch.org 国内龟速,直接把 ~14MB 的 music-8000 包放仓库里。
# tarball 解压结构:music/<rate>/*.wav,直接铺到 sounds/ 顶层即可。
# 幂等:目标目录非空则跳过。
# 追加新包:把 .tar.gz 丢进 install/conf/freeswitch/sounds/ 即可,自动识别。
_fs_install_sounds() {
  install -d -m 0755 "$FS_PREFIX/sounds"
  local sounds_dir tarball
  sounds_dir="$(_fs_install_dir)/conf/freeswitch/sounds"
  if [ ! -d "$sounds_dir" ]; then
    echo "[freeswitch] $sounds_dir 不存在,跳过 sounds 安装" >&2
    return 0
  fi
  shopt -s nullglob
  for tarball in "$sounds_dir"/*.tar.gz; do
    if ! tar -xzf "$tarball" -C "$FS_PREFIX/sounds/"; then
      echo "[freeswitch] 解压 sounds 失败: $tarball" >&2
    else
      echo "[freeswitch] 已安装 sounds: $(basename "$tarball")" >&2
    fi
  done
  shopt -u nullglob
}

# 在 /usr/bin 建软链,让 freeswitch / fs_cli 命令在 PATH 中直接可用。
# 独立函数:do_install 每次都调用(放在 _fs_build_from_source 里会被幂等检查跳过)。
_fs_install_symlinks() {
  ln -sf "$FS_PREFIX/bin/freeswitch" /usr/bin/freeswitch
  ln -sf "$FS_PREFIX/bin/fs_cli" /usr/bin/fs_cli
}

# do_install 时强制部署仓库 conf:make install 会自动写一份"默认 conf"
# (~200 文件),覆盖我们仓库版。所以这里**先备份现有 conf 到带时间戳的目录**,
# 再清空 + 拷贝仓库版。reconfigure 不调用本函数,所以运维手改的 conf 不会丢。
_fs_install_conf() {
  local install_dir backup_dir
  install_dir="$(_fs_install_dir)"
  install -d -m 0755 "$FS_PREFIX/conf"
  if [ -n "$(ls -A "$FS_PREFIX/conf" 2>/dev/null)" ]; then
    backup_dir="${FS_PREFIX}/conf.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$FS_PREFIX/conf" "$backup_dir"
    install -d -m 0755 "$FS_PREFIX/conf"
    echo "[freeswitch] 现有 conf 已备份到 $backup_dir(install 用仓库版覆盖;reconfigure 永远不动 conf)" >&2
  fi
  cp -r "$install_dir/conf/freeswitch/conf/." "$FS_PREFIX/conf/"
  echo "[freeswitch] 已落地仓库 conf 到 $FS_PREFIX/conf/" >&2
}

# 把 FS_PREFIX/recordings 和 FS_PREFIX/audios 软链到 /data/{recordings,audios},
# 让录音/业务音频实际写到大盘 /data 而非系统盘 /usr/local。
# 处理顺序:确保 /data 目标目录存在 → 备份 FS 下已有内容(若有非链接) → ln -sfn
_fs_install_data_links() {
  install -d -m 0755 /data/recordings
  install -d -m 0755 /data/audios
  chown freeswitch:freeswitch /data/recordings /data/audios 2>/dev/null || true

  local target src bak
  for pair in "recordings:/data/recordings" "audios:/data/audios"; do
    src="$FS_PREFIX/${pair%%:*}"
    target="${pair##*:}"
    if [ -L "$src" ]; then
      # 已是软链,直接覆盖(ln -sfn 保证指向正确)
      ln -sfn "$target" "$src"
    elif [ -d "$src" ]; then
      # 真目录:先把已有内容 mv 到 /data 目标下,再删除原目录、建软链
      bak="${src}.bak.$(date +%Y%m%d-%H%M%S)"
      mv "$src" "$bak"
      # 备份目录里如果有文件,合并到 /data(忽略已存在同名)
      if [ -n "$(ls -A "$bak" 2>/dev/null)" ]; then
        cp -rn "$bak/." "$target/" 2>/dev/null || true
        echo "[freeswitch] $src 原有内容已备份到 $bak 并合并到 $target" >&2
      else
        rmdir "$bak" 2>/dev/null || true
      fi
      ln -sfn "$target" "$src"
    else
      # 不存在:直接建链
      ln -sfn "$target" "$src"
    fi
  done
  echo "[freeswitch] 已建立软链:$FS_PREFIX/recordings → /data/recordings,$FS_PREFIX/audios → /data/audios" >&2
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
  _fs_install_sounds
  _fs_install_symlinks
  _fs_install_conf
  _fs_install_data_links
  _fs_install_unit
  systemctl enable freeswitch
  # 显式 restart:重跑 install 时(幂等场景)freeswitch 可能已经在跑,
  # 需要让新 conf / unit 立刻生效,与其他 service 模块约定一致。
  systemctl restart freeswitch
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
