#!/usr/bin/env bash
# LLVM coverage for selected production modules, not a whole-project percentage.
set -euo pipefail
[[ $# -eq 0 ]] || { echo "usage: $0" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${root}"
# Capture separately: command substitutions used as another command's argument
# do not propagate Git failure through errexit. Recheck the revision at export.
source_revision="$(git rev-parse --verify HEAD)"
mkdir -p build/zime-coverage
report="$(mktemp -d "${root}/build/zime-coverage/run.XXXXXX")"
mkdir "${report}/raw" "${report}/module-cache"
source tests/swift_test_scratch.sh
linnet_swift_scratch_init
export LLVM_PROFILE_FILE="${report}/raw/%m-%p.profraw"
objects=()
measure() {
  local name="$1"
  shift
  linnet_test_run 300 xcrun swiftc -warnings-as-errors -parse-as-library \
    -module-cache-path "${report}/module-cache" \
    -target arm64-apple-macosx13.0 -profile-generate -profile-coverage-mapping \
    -framework AppKit -framework Security "$@" -o "${report}/${name}"
  linnet_test_run 300 "${report}/${name}"
  objects+=(-object "${report}/${name}")
}
measure translation sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  tests/ZIMETranslationTests.swift
measure translation-http sources/ZIMETranslationProvider.swift tests/ZIMETranslationHTTPTests.swift
measure translation-settings sources/ZIMETranslationProvider.swift \
  sources/LinnetSettings/ZIMETranslationSettingsModel.swift tests/ZIMETranslationSettingsTests.swift
measure candidate-translator sources/LinnetPackContract.swift sources/LinnetDataChannel.swift \
  sources/LinnetDataRegistry.swift sources/LinnetDirectoryDelta.swift \
  sources/LinnetDataRegistryTransactions.swift sources/LinnetDataRegistryStorage.swift \
  sources/LinnetSettings/SettingsContract.swift sources/LinnetCandidatePresentation.swift \
  sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  sources/ZIMECandidateTranslator.swift tests/ZIMECandidateTranslatorTests.swift \
  tests/ZIMECandidateTranslatorBoundaryTests.swift tests/ZIMECandidateTranslatorTestSupport.swift
measure installer sources/LinnetDirectoryDelta.swift sources/ZIMEInstallTransaction.swift \
  tests/ZIMEInstallTransactionTests.swift
linnet_test_run 300 xcrun llvm-profdata merge -sparse "${report}"/raw/*.profraw -o "${report}/coverage.profdata"
linnet_test_run 300 xcrun llvm-cov export "${objects[@]}" -instr-profile="${report}/coverage.profdata" \
  -ignore-filename-regex='/tests/|/Applications/|/usr/' > "${report}/coverage.json"
linnet_test_run 300 xcrun llvm-cov report "${objects[@]}" -instr-profile="${report}/coverage.profdata" \
  -ignore-filename-regex='/tests/|/Applications/|/usr/' > "${report}/report.txt"
linnet_test_run 300 xcrun llvm-cov show "${objects[@]}" -instr-profile="${report}/coverage.profdata" \
  -ignore-filename-regex='/tests/|/Applications/|/usr/' -format=html \
  -output-dir="${report}/html"
ruby tests/verify_coverage_gate.rb
ruby tests/zime_coverage_gate.rb "${root}" "${report}" "${source_revision}"
echo "ZIME scoped coverage: PASS; report=${report}/report.txt"
