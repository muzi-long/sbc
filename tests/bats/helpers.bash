# tests/bats/helpers.bash
# shellcheck shell=bash
# shellcheck disable=SC2154  # BATS_TEST_FILENAME is set by bats at runtime
# NOTE: assumes all .bats files live exactly at tests/bats/*.bats (one level deep)
# 如果以后引入 tests/bats/subdir/*.bats,需要重新计算 REPO_ROOT
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
export REPO_ROOT
