#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "detect_ubuntu reads codename from os-release file" {
  cat > "$TEST_TMPDIR/os-release" <<EOF
ID=ubuntu
VERSION_ID="22.04"
VERSION_CODENAME=jammy
EOF
  run detect_ubuntu "$TEST_TMPDIR/os-release"
  [ "$status" -eq 0 ]
  [ "$output" = "jammy" ]
}

@test "detect_ubuntu fails on debian" {
  cat > "$TEST_TMPDIR/os-release" <<EOF
ID=debian
VERSION_CODENAME=bookworm
EOF
  run detect_ubuntu "$TEST_TMPDIR/os-release"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Ubuntu"* ]]
}

@test "detect_ubuntu fails when codename missing" {
  cat > "$TEST_TMPDIR/os-release" <<EOF
ID=ubuntu
EOF
  run detect_ubuntu "$TEST_TMPDIR/os-release"
  [ "$status" -ne 0 ]
}

@test "require_root passes when EUID=0" {
  _EUID_OVERRIDE=0 run require_root
  [ "$status" -eq 0 ]
}

@test "require_root fails when EUID!=0" {
  _EUID_OVERRIDE=1000 run require_root
  [ "$status" -ne 0 ]
  [[ "$output" == *"root"* ]]
}
