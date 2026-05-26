#!/usr/bin/env bats
load 'helpers'

setup() {
  source "$REPO_ROOT/install/lib/common.sh"
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "render_tpl replaces single placeholder" {
  echo "hello __NAME__" > "$TEST_TMPDIR/in"
  run render_tpl "$TEST_TMPDIR/in" "$TEST_TMPDIR/out" "NAME=world"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/out")" = "hello world" ]
}

@test "render_tpl replaces multiple keys" {
  printf 'a=__A__ b=__B__\n' > "$TEST_TMPDIR/in"
  run render_tpl "$TEST_TMPDIR/in" "$TEST_TMPDIR/out" "A=1" "B=2"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/out")" = "a=1 b=2" ]
}

@test "render_tpl handles values containing slash and ampersand" {
  echo "url=__URL__" > "$TEST_TMPDIR/in"
  run render_tpl "$TEST_TMPDIR/in" "$TEST_TMPDIR/out" "URL=http://a/b&c=d"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/out")" = "url=http://a/b&c=d" ]
}

@test "render_tpl fails when placeholder remains unreplaced" {
  printf 'x=__X__ y=__Y__\n' > "$TEST_TMPDIR/in"
  run render_tpl "$TEST_TMPDIR/in" "$TEST_TMPDIR/out" "X=1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"__Y__"* ]]
}

@test "render_tpl handles same placeholder appearing twice" {
  printf '__A__-__A__\n' > "$TEST_TMPDIR/in"
  run render_tpl "$TEST_TMPDIR/in" "$TEST_TMPDIR/out" "A=x"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/out")" = "x-x" ]
}
