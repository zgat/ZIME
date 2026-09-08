#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${root}"
make zime-install-helper
xcrun swiftc -warnings-as-errors -sdk "$(xcrun --show-sdk-path)" \
  -module-cache-path build/swift-module-cache \
  sources/LinnetDirectoryDelta.swift sources/ZIMEInstallTransaction.swift \
  tests/ZIMEInstallTransactionTests.swift -o build/zime-install-tests
build/zime-install-tests
for script in scripts/install-zime scripts/update-zime-app scripts/build-zime-delivery package/zime-installer-scripts/postinstall; do
  /bin/zsh -n "${script}"
done
! rg 'pkill|kill -9|open -gj|open -j' scripts/install-zime scripts/update-zime-app tools/ZIMEInstallHelper.swift
codesign --verify --strict build/zime-install-helper
echo 'ZIME installer entrypoints: PASS'
