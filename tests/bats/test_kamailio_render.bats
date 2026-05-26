#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TEST_TMPDIR="$(mktemp -d)"
}
teardown() { rm -rf "$TEST_TMPDIR"; }

@test "kamailio.cfg renders all placeholders" {
  run render_tpl "$REPO_ROOT/install/conf/kamailio/kamailio.cfg.tpl" "$TEST_TMPDIR/cfg" \
    "PUBLIC_IP=1.2.3.4" "PRIVATE_IP=10.0.0.1" "LISTEN_IFACE=eth0" \
    "SIP_UDP_PORT=15060" "SIP_TCP_PORT=15062" \
    "KAM_ALIAS_1=a.test" "KAM_ALIAS_2=b.test" \
    "DB_HOST=db.host" "DB_PORT=3306" "DB_USER=u" "DB_PASS=p" "DB_NAME=n" \
    "REDIS_HOST=r.host" "REDIS_PORT=6379" "REDIS_PASS=pw" \
    "RTPE_NG_PORT=2223"
  [ "$status" -eq 0 ]
  grep -q 'listen=udp:eth0:15060 advertise 1.2.3.4:15060' "$TEST_TMPDIR/cfg"
  grep -q 'alias="a.test"' "$TEST_TMPDIR/cfg"
  grep -q 'mysql://u:p@db.host:3306/n' "$TEST_TMPDIR/cfg"
  grep -q 'addr=r.host;port=6379;pass=pw' "$TEST_TMPDIR/cfg"
  grep -q 'udp:127.0.0.1:2223' "$TEST_TMPDIR/cfg"
  ! grep -qE '__[A-Z_]+__' "$TEST_TMPDIR/cfg"
}

@test "kamailio.cfg missing DB_PASS fails" {
  run render_tpl "$REPO_ROOT/install/conf/kamailio/kamailio.cfg.tpl" "$TEST_TMPDIR/cfg" \
    "PUBLIC_IP=1.2.3.4" "PRIVATE_IP=10.0.0.1" "LISTEN_IFACE=eth0" \
    "SIP_UDP_PORT=15060" "SIP_TCP_PORT=15062" \
    "KAM_ALIAS_1=a.test" "KAM_ALIAS_2=b.test" \
    "DB_HOST=db.host" "DB_PORT=3306" "DB_USER=u" "DB_NAME=n" \
    "REDIS_HOST=r.host" "REDIS_PORT=6379" "REDIS_PASS=pw" \
    "RTPE_NG_PORT=2223"
  [ "$status" -ne 0 ]
}
