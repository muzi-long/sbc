#!/usr/bin/env bats
load 'helpers'

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export STUB_LOG="$TEST_TMPDIR/log"
  : > "$STUB_LOG"
  # 让 install.sh 用 stub 当作 fake kamailio/rtpengine/caddy 模块
  STUB_SVC_DIR="$TEST_TMPDIR/services"
  mkdir -p "$STUB_SVC_DIR"
  for s in kamailio rtpengine caddy; do
    cp "$REPO_ROOT/install/services/_stub.sh" "$STUB_SVC_DIR/$s.sh"
  done
  export INSTALL_SERVICES_DIR="$STUB_SVC_DIR"
  # bypass root 校验
  export SKIP_ROOT_CHECK=1
  # bypass OS 校验
  export SKIP_OS_CHECK=1
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "no subcommand exits non-zero" {
  run "$REPO_ROOT/install/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"用法"* ]]
}

@test "install kamailio dispatches to kamailio do_install" {
  run "$REPO_ROOT/install/install.sh" install kamailio
  [ "$status" -eq 0 ]
  grep -q "stub:install" "$STUB_LOG"
}

@test "reconfigure caddy dispatches to caddy do_reconfigure" {
  run "$REPO_ROOT/install/install.sh" reconfigure caddy
  [ "$status" -eq 0 ]
  grep -q "stub:reconfigure" "$STUB_LOG"
}

@test "install with unknown service exits non-zero and lists known" {
  run "$REPO_ROOT/install/install.sh" install nonesuch
  [ "$status" -ne 0 ]
  [[ "$output" == *"kamailio"* ]]
  [[ "$output" == *"rtpengine"* ]]
  [[ "$output" == *"caddy"* ]]
}

@test "install with no service in non-tty exits with hint" {
  run bash -c "'$REPO_ROOT/install/install.sh' install </dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"显式"* || "$output" == *"non-interactive"* ]]
}

@test "install with multiple services dispatches each" {
  run "$REPO_ROOT/install/install.sh" install kamailio caddy
  [ "$status" -eq 0 ]
  [ "$(grep -c 'stub:install' "$STUB_LOG")" -eq 2 ]
}
