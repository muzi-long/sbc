#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "detect_debian_bookworm reads ID=debian + codename=bookworm passes" {
  cat > "$TEST_TMPDIR/os-release" <<EOF
ID=debian
VERSION_ID="12"
VERSION_CODENAME=bookworm
EOF
  run detect_debian_bookworm "$TEST_TMPDIR/os-release"
  [ "$status" -eq 0 ]
}

@test "detect_debian_bookworm fails on ubuntu" {
  cat > "$TEST_TMPDIR/os-release" <<EOF
ID=ubuntu
VERSION_ID="22.04"
VERSION_CODENAME=jammy
EOF
  run detect_debian_bookworm "$TEST_TMPDIR/os-release"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Debian"* ]]
}

@test "detect_debian_bookworm fails on debian bullseye" {
  cat > "$TEST_TMPDIR/os-release" <<EOF
ID=debian
VERSION_ID="11"
VERSION_CODENAME=bullseye
EOF
  run detect_debian_bookworm "$TEST_TMPDIR/os-release"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bookworm"* ]]
}

@test "detect_debian_bookworm fails when VERSION_CODENAME missing" {
  cat > "$TEST_TMPDIR/os-release" <<EOF
ID=debian
VERSION_ID="12"
EOF
  run detect_debian_bookworm "$TEST_TMPDIR/os-release"
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
