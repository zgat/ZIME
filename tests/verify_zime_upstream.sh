#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
scratch="$(mktemp -d /tmp/zime-upstream-test.XXXXXX)"
trap 'rm -f -- "${scratch}/encoding"; rmdir "${scratch}"' EXIT
cd "${root}"
scripts/upstream-sync verify
xcrun clang++ -std=c++17 -Wall -Wextra -Werror \
  tests/zime_grammar_encoding_test.cc lib/rime-plugins/librime-octagram.dylib \
  -o "${scratch}/encoding"
DYLD_LIBRARY_PATH="${root}/lib:${root}/lib/rime-plugins" "${scratch}/encoding"
strings lib/rime-plugins/librime-lua.dylib | rg -q 'Lua 5\.4\.9'
echo 'ZIME embedded Lua: PASS (5.4.9; not a 5.5 migration)'
