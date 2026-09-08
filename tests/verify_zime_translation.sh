#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/ruby tests/verify_zime_lexicon.rb
mkdir -p build/zime-tests/module-cache
/usr/bin/xcrun swiftc -warnings-as-errors -parse-as-library \
  -module-cache-path build/zime-tests/module-cache \
  -target arm64-apple-macosx13.0 -framework Security \
  sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  tests/ZIMETranslationTests.swift -o build/zime-tests/translation
build/zime-tests/translation
/usr/bin/xcrun swiftc -warnings-as-errors -parse-as-library \
  -module-cache-path build/zime-tests/module-cache \
  -target arm64-apple-macosx13.0 -framework Security \
  sources/ZIMETranslationProvider.swift sources/LinnetSettings/ZIMETranslationSettingsModel.swift \
  tests/ZIMETranslationSettingsTests.swift -o build/zime-tests/translation-settings
build/zime-tests/translation-settings
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
bash tests/verify_zime_host_routing.sh
