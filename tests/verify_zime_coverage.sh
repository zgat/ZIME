#!/usr/bin/env bash
# LLVM coverage for selected production modules, not a whole-project percentage.
set -euo pipefail
[[ $# -eq 0 ]] || { echo "usage: $0" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${root}"
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
  xcrun swiftc -warnings-as-errors -parse-as-library \
    -module-cache-path "${report}/module-cache" \
    -target arm64-apple-macosx13.0 -profile-generate -profile-coverage-mapping \
    -framework AppKit -framework Security "$@" -o "${report}/${name}"
  "${report}/${name}"
  objects+=(-object "${report}/${name}")
}
measure translation sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  tests/ZIMETranslationTests.swift
measure translation-settings sources/ZIMETranslationProvider.swift \
  sources/LinnetSettings/ZIMETranslationSettingsModel.swift tests/ZIMETranslationSettingsTests.swift
measure candidate-translator sources/LinnetPackContract.swift sources/LinnetDataChannel.swift \
  sources/LinnetDataRegistry.swift sources/LinnetDirectoryDelta.swift \
  sources/LinnetDataRegistryTransactions.swift sources/LinnetDataRegistryStorage.swift \
  sources/LinnetSettings/SettingsContract.swift sources/LinnetCandidatePresentation.swift \
  sources/ZIMELocalLexicon.swift sources/ZIMETranslationProvider.swift \
  sources/ZIMECandidateTranslator.swift tests/ZIMECandidateTranslatorTests.swift
measure installer sources/LinnetDirectoryDelta.swift sources/ZIMEInstallTransaction.swift \
  tests/ZIMEInstallTransactionTests.swift
xcrun llvm-profdata merge -sparse "${report}"/raw/*.profraw -o "${report}/coverage.profdata"
xcrun llvm-cov export "${objects[@]}" -instr-profile="${report}/coverage.profdata" \
  -ignore-filename-regex='/tests/|/Applications/|/usr/' > "${report}/coverage.json"
xcrun llvm-cov report "${objects[@]}" -instr-profile="${report}/coverage.profdata" \
  -ignore-filename-regex='/tests/|/Applications/|/usr/' > "${report}/report.txt"
xcrun llvm-cov show "${objects[@]}" -instr-profile="${report}/coverage.profdata" \
  -ignore-filename-regex='/tests/|/Applications/|/usr/' -format=html \
  -output-dir="${report}/html"
ruby -rjson -e '
  root, dir, revision = ARGV
  files = JSON.parse(File.read(File.join(dir, "coverage.json"))).fetch("data").flat_map { |d| d.fetch("files") }
  abort "coverage contains unexpected source files" unless files.all? { |f| f.fetch("filename").start_with?(root + "/sources/") }
  abort "coverage has duplicate source files" unless files.map { |f| f["filename"] }.uniq.size == files.size
  totals = %w[lines functions regions].to_h { |kind|
    count = files.sum { |f| f.fetch("summary").fetch(kind).fetch("count") }
    covered = files.sum { |f| f.fetch("summary").fetch(kind).fetch("covered") }
    abort "empty coverage: #{kind}" unless count > 0 && covered > 0
    [kind, {"count" => count, "covered" => covered, "percent" => (100.0 * covered / count).round(2)}]
  }
  result = {"scope" => "selected Swift translation/settings-model/candidate-translator/installer fixtures and their production dependencies; NOT whole-project coverage",
    "source_revision" => revision, "source_dirty" => !IO.popen(["git", "status", "--porcelain=v1"], &:read).empty?,
    "branch_coverage" => "not measured by this Swift instrumentation",
    "files" => files.map { |f| f["filename"].delete_prefix(root + "/") }, "totals" => totals}
  File.write(File.join(dir, "summary.json"), JSON.pretty_generate(result) + "\n")
  puts JSON.pretty_generate(result)
' "${root}" "${report}" "$(git rev-parse HEAD)"
echo "ZIME scoped coverage: PASS; report=${report}/report.txt"
