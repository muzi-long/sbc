#!/usr/bin/env bats
load 'helpers'

@test "repo root resolves" {
  [ -n "$REPO_ROOT" ]
  [ -d "$REPO_ROOT/install" ] || skip "install dir not yet created"
}

@test "bash version >= 4" {
  [ "${BASH_VERSINFO[0]}" -ge 4 ]
}
