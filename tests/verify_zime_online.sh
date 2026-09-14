#!/usr/bin/env bash
# Explicit live-service smoke test; excluded from default/CI gates.
set -euo pipefail
[[ $# -eq 1 && "$1" == --allow-network ]] || {
  echo "NOT_EXERCISED: pass --allow-network only after consenting to two fixed translation requests and Keychain access." >&2
  exit 64
}
cd "$(dirname "$0")/.."
mkdir -p build/zime-tests/module-cache
xcrun swiftc -warnings-as-errors -parse-as-library -framework Security \
  -module-cache-path build/zime-tests/module-cache -target arm64-apple-macosx13.0 \
  sources/ZIMETranslationProvider.swift tests/ZIMEOnlineTranslationSmoke.swift \
  -o build/zime-tests/online-smoke
build/zime-tests/online-smoke --allow-network
