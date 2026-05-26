#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 用官方 bats docker 镜像,把仓库挂进去
exec docker run --rm \
  -v "${REPO_ROOT}:/code" \
  -w /code \
  bats/bats:1.10.0 \
  tests/bats
