#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/ruby tests/verify_zime_lexicon.rb
source tests/swift_test_scratch.sh
linnet_swift_scratch_init
source tests/swift_test_cache.sh
linnet_swift_cache_init "${PWD}" "${scratch}"
compile_run() {
  local name="$1"
  shift
  linnet_swift_compile "${name}" -warnings-as-errors -parse-as-library \
    -sdk "${LINNET_MACOS_SDK}" -target arm64-apple-macosx13.0 -framework Security "$@"
  "${LINNET_SWIFT_COMPILED_BINARY}"
}
compile_run translation \
  sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  tests/ZIMETranslationTests.swift
compile_run translation-http \
  sources/ZIMETranslationProvider.swift tests/ZIMETranslationHTTPTests.swift
compile_run translation-settings \
  sources/ZIMETranslationProvider.swift sources/LinnetSettings/ZIMETranslationSettingsModel.swift \
  tests/ZIMETranslationSettingsTests.swift
compile_run candidate-translator -framework AppKit \
  sources/LinnetPackContract.swift sources/LinnetDataChannel.swift \
  sources/LinnetDataRegistry.swift sources/LinnetDirectoryDelta.swift \
  sources/LinnetDataRegistryTransactions.swift sources/LinnetDataRegistryStorage.swift \
  sources/LinnetSettings/SettingsContract.swift sources/LinnetCandidatePresentation.swift \
  sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  sources/ZIMECandidateTranslator.swift tests/ZIMECandidateTranslatorTests.swift
bash tests/verify_zime_host_routing.sh
