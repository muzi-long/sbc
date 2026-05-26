#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
}

@test "require_vars passes when all set" {
  FOO=a BAR=b run require_vars FOO BAR
  [ "$status" -eq 0 ]
}

@test "require_vars fails when one missing, lists name" {
  FOO=a BAR="" run require_vars FOO BAR
  [ "$status" -ne 0 ]
  [[ "$output" == *"BAR"* ]]
}

@test "require_vars lists all missing names" {
  FOO="" BAR="" BAZ=ok run require_vars FOO BAR BAZ
  [ "$status" -ne 0 ]
  [[ "$output" == *"FOO"* ]]
  [[ "$output" == *"BAR"* ]]
  [[ "$output" != *"BAZ"* ]]
}

@test "require_vars treats unset as missing" {
  unset UNSET_VAR
  run require_vars UNSET_VAR
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNSET_VAR"* ]]
}
