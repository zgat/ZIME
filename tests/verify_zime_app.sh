#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
[[ $# -eq 2 || $# -eq 3 ]] || { echo "usage: $0 APP local|release [SOURCE_REVISION]" >&2; exit 64; }
ruby -r "${root}/scripts/lib/zime_release" -e '
  ZIMERelease.verify_app(ARGV[0], ARGV[1], ARGV[2], ARGV[3])
  puts "ZIME App: PASS (identity, version, architecture, dictionary, privacy and profile-specific signature)"
' "${root}" "$@"
