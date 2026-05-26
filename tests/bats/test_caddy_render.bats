#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "Caddyfile renders all placeholders" {
  run render_tpl "$REPO_ROOT/install/conf/caddy/Caddyfile.tpl" "$TEST_TMPDIR/Caddyfile" \
    "CADDY_API_DOMAIN=api.test" \
    "CADDY_API_UPSTREAM=localhost:8080" \
    "CADDY_APP_DOMAIN=app.test" \
    "CADDY_APP_UPSTREAM=localhost:3000" \
    "CADDY_WEBRTC_DOMAIN=ws.test" \
    "CADDY_WEBRTC_UPSTREAM=127.0.0.1:15062"
  [ "$status" -eq 0 ]
  grep -q "api.test" "$TEST_TMPDIR/Caddyfile"
  grep -q "localhost:8080" "$TEST_TMPDIR/Caddyfile"
  grep -q "ws.test" "$TEST_TMPDIR/Caddyfile"
  grep -q "127.0.0.1:15062" "$TEST_TMPDIR/Caddyfile"
  ! grep -q "__CADDY_" "$TEST_TMPDIR/Caddyfile"
}

@test "Caddyfile missing one var fails with leak detection" {
  run render_tpl "$REPO_ROOT/install/conf/caddy/Caddyfile.tpl" "$TEST_TMPDIR/Caddyfile" \
    "CADDY_API_DOMAIN=api.test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"__CADDY_"* ]]
}
