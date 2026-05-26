#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TEST_TMPDIR="$(mktemp -d)"
}
teardown() { rm -rf "$TEST_TMPDIR"; }

@test "rtpengine.conf renders all placeholders" {
  run render_tpl "$REPO_ROOT/install/conf/rtpengine/rtpengine.conf.tpl" "$TEST_TMPDIR/out" \
    "PRIVATE_IP=10.0.0.1" "PUBLIC_IP=1.2.3.4" \
    "RTPE_NG_PORT=2223" "RTPE_PORT_MIN=40000" "RTPE_PORT_MAX=60000"
  [ "$status" -eq 0 ]
  grep -q "priv/10.0.0.1;pub/10.0.0.1!1.2.3.4" "$TEST_TMPDIR/out"
  grep -q "listen-ng = 0.0.0.0:2223" "$TEST_TMPDIR/out"
  grep -q "port-min = 40000" "$TEST_TMPDIR/out"
  grep -q "port-max = 60000" "$TEST_TMPDIR/out"
  ! grep -q "__" "$TEST_TMPDIR/out"
}

@test "rtpengine.conf missing PUBLIC_IP fails" {
  run render_tpl "$REPO_ROOT/install/conf/rtpengine/rtpengine.conf.tpl" "$TEST_TMPDIR/out" \
    "PRIVATE_IP=10.0.0.1" \
    "RTPE_NG_PORT=2223" "RTPE_PORT_MIN=40000" "RTPE_PORT_MAX=60000"
  [ "$status" -ne 0 ]
}
