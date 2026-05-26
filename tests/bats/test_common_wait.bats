#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
}

@test "wait_for_active returns 0 immediately when systemctl says active" {
  # mock systemctl 总是返回 active
  systemctl() {
    if [ "$1" = "is-active" ]; then
      return 0
    fi
  }
  export -f systemctl
  run wait_for_active fake.service 5
  [ "$status" -eq 0 ]
}

@test "wait_for_active times out when systemctl always fails" {
  systemctl() {
    return 1
  }
  export -f systemctl
  # 短 timeout 防止测试跑太久
  run wait_for_active fake.service 2
  [ "$status" -ne 0 ]
}
