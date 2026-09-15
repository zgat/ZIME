#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/zime-tests/module-cache
compiler="$(xcrun --find swiftc)"
host_library="$(cd "$(dirname "${compiler}")/../lib/swift/host" && pwd -P)"
xcrun swift -module-cache-path build/zime-tests/module-cache \
  -I "${host_library}" -L "${host_library}" -lSwiftParser -lSwiftSyntax \
  tests/extract_host_test_declarations.swift sources/SquirrelInputController+RimeSession.swift \
  > build/zime-tests/host-routing.swift
xcrun swiftc -warnings-as-errors -parse-as-library -enable-bare-slash-regex \
  -module-cache-path build/zime-tests/module-cache -framework AppKit \
  sources/LinnetPackContract.swift sources/LinnetDataChannel.swift \
  sources/LinnetDataRegistry.swift sources/LinnetDirectoryDelta.swift \
  sources/LinnetDataRegistryTransactions.swift sources/LinnetDataRegistryStorage.swift \
  sources/LinnetSettings/SettingsContract.swift sources/LinnetCandidatePresentation.swift \
  sources/SquirrelInputController+Bilingual.swift tests/ZIMEHostRoutingFixture.swift \
  build/zime-tests/host-routing.swift -o build/zime-tests/host-routing
build/zime-tests/host-routing
