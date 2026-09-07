#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/zime-tests/module-cache
/usr/bin/xcrun swiftc -warnings-as-errors -parse-as-library \
  -module-cache-path build/zime-tests/module-cache \
  -target arm64-apple-macosx13.0 -framework Security \
  sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  tests/ZIMETranslationTests.swift -o build/zime-tests/translation
build/zime-tests/translation
/usr/bin/xcrun swiftc -warnings-as-errors -parse-as-library \
  -module-cache-path build/zime-tests/module-cache \
  -target arm64-apple-macosx13.0 -framework AppKit -framework Security \
  sources/LinnetPackContract.swift sources/LinnetDataChannel.swift \
  sources/LinnetDataRegistry.swift sources/LinnetDirectoryDelta.swift \
  sources/LinnetDataRegistryTransactions.swift sources/LinnetDataRegistryStorage.swift \
  sources/LinnetSettings/SettingsContract.swift sources/LinnetCandidatePresentation.swift \
  sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  sources/ZIMECandidateTranslator.swift tests/ZIMECandidateTranslatorTests.swift \
  -o build/zime-tests/candidate-translator
build/zime-tests/candidate-translator
