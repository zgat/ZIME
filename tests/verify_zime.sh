#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${repo_root}"

fail() {
  echo "verify_zime: FAIL: $*" >&2
  exit 1
}

[[ "$(sed -n 's/^LINNET_PRODUCT_NAME = //p' config/LinnetProduct.xcconfig)" == ZIME ]] ||
  fail "product name"
[[ "$(sed -n 's/^LINNET_BUNDLE_IDENTIFIER = //p' config/LinnetProduct.xcconfig)" == com.zime.inputmethod.ZIME ]] ||
  fail "bundle identifier"

info=resources/Info.plist
/usr/bin/plutil -lint "${info}" >/dev/null
[[ "$(/usr/bin/plutil -extract TISInputSourceID raw -o - "${info}")" == com.zime.inputmethod.ZIME ]] ||
  fail "bundle input source ID"
for mode in Hans Hant; do
  mode_root=":ComponentInputModeDict:tsInputModeListKey:com.zime.inputmethod.ZIME.${mode}"
  [[ "$(/usr/libexec/PlistBuddy -c "Print ${mode_root}:TISInputSourceID" "${info}")" == "com.zime.inputmethod.ZIME.${mode}" ]] ||
    fail "${mode} mode ID"
done
[[ "$(/usr/libexec/PlistBuddy -c \
  'Print :ComponentInputModeDict:tsInputModeListKey:com.zime.inputmethod.ZIME.Hans:TISIntendedLanguage' \
  "${info}")" == zh-Hans ]] || fail "Hans language"
[[ "$(/usr/libexec/PlistBuddy -c \
  'Print :ComponentInputModeDict:tsInputModeListKey:com.zime.inputmethod.ZIME.Hant:TISIntendedLanguage' \
  "${info}")" == zh-Hant ]] || fail "Hant language"

ruby -ryaml -e '
  schemas = YAML.load_file("data/linnet/default.yaml").fetch("schema_list")
  abort unless schemas.map { |row| row.fetch("schema") } == %w[linnet_zh_pinyin linnet_en]
' || fail "full-pinyin-only schema list"

rg -Fq 'LookupEnglishTranslations' plugins/smart_english/smart_english_index.cc ||
  fail "reverse dictionary lookup"
rg -Fq 'counts.namespaces["m/en"]' tools/LinnetEnglishDataGenerator.swift ||
  fail "reverse dictionary projection"
rg -Fq 'ZIMENullCloudTranslationProvider' sources/LinnetCandidatePresentation.swift ||
  fail "null cloud provider"
if rg -n 'URLSession|NSURLConnection|curl_easy|CFNetwork' \
  sources/SquirrelInputController.swift sources/LinnetCandidatePresentation.swift \
  plugins/smart_english; then
  fail "candidate translation path contains a network client"
fi
rg -Fq 'pendingCommitOverride' sources/SquirrelInputController.swift ||
  fail "translation-only commit boundary"

if [[ $# -gt 0 ]]; then
  app="$1"
  [[ -d "${app}" && ! -L "${app}" ]] || fail "missing app: ${app}"
  built_info="${app}/Contents/Info.plist"
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "${built_info}")" == com.zime.inputmethod.ZIME ]] ||
    fail "built bundle identity"
  [[ "$(/usr/bin/plutil -extract CFBundleDisplayName raw -o - "${built_info}")" == ZIME ]] ||
    fail "built display name"
  while IFS= read -r binary; do
    [[ "$(/usr/bin/lipo -archs "${binary}")" == arm64 ]] ||
      fail "non-arm64 binary: ${binary}"
  done < <(find "${app}" -type f -print | while IFS= read -r path; do
    file -b "${path}" | grep -q Mach-O && printf '%s\n' "${path}"
  done)
fi

echo "verify_zime: PASS"
