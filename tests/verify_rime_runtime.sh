#!/usr/bin/env bash

# Native engine acceptance. Each invocation stages isolated data and builds its
# harness once; focused probes have explicit scopes, not full-suite semantics.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${repo_root}"

runtime_probe="${1:-}"
probes=(
  --zime-bilingual-probe --zime-alphanumeric-probe --zime-case-probe
  --zime-shortcuts-probe --zime-paging-probe --zime-soak-probe --mixed-input-probe
  --mixed-latency-probe --warm-session-probe --cold-client-probe
  --profile-key-matrix-probe --fast-config-reload-probe --live-sync-probe
)
if [[ $# -eq 1 && "$1" == --list-probes ]]; then
  printf '%s\n' "${probes[@]}"
  exit 0
fi
if [[ $# -gt 1 ]]; then
  echo "usage: $0 [PROBE | --list-probes] (one probe per invocation)" >&2
  exit 64
fi
valid_probe=0
for probe in "${probes[@]}"; do
  [[ "${runtime_probe}" != "${probe}" ]] || valid_probe=1
done
if [[ $# -ne 0 && "${valid_probe}" -eq 0 ]]; then
  echo "usage: $0 [PROBE | --list-probes]" >&2
  exit 64
fi

scratch="$(mktemp -d /tmp/linnet-rime-runtime.XXXXXX)"
cleanup() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ "${status}" -ne 0 && "${LINNET_KEEP_FAILED_RIME_FIXTURE:-0}" == 1 ]]; then
    echo "Failed isolated Rime fixture retained: ${scratch}" >&2
    exit "${status}"
  fi
  [[ "${scratch}" == /tmp/linnet-rime-runtime.* ]] && /bin/rm -rf -- "${scratch}"
  exit "${status}"
}
trap cleanup EXIT
source tests/test_runner.sh

phase_started=0
begin_phase() {
  phase_started="${SECONDS}"
  printf '==> Rime runtime: %s\n' "$1"
}
end_phase() {
  printf '<== Rime runtime: PASS in %ss: %s\n' \
    "$((SECONDS - phase_started))" "$1"
}

begin_phase "stage isolated product data"
shared="${scratch}/shared"
user="${scratch}/user"
logs="${scratch}/logs"
mkdir -p "${shared}/opencc" "${user}" "${logs}"
cp -R data/plum/. "${shared}/"
# The ignored data/plum directory is a generated cache and can legitimately
# predate the current source checkout. Native acceptance must consume the
# canonical public schemas and default owner, just as packaging does when it
# stages a candidate. No wrapper profile may be accepted from an old cache.
for schema in data/linnet/*.schema.yaml; do
  cp "${schema}" "${shared}/$(basename "${schema}")"
done
cp data/linnet/default.yaml "${shared}/default.yaml"
# Reproduce a retained pre-0.1.12 language pack. Core projections must install
# the new segmentor once, without needing a dictionary-pack replacement.
/usr/bin/ruby -e '
  ARGV.each do |path|
    source = File.binread(path)
    line = "    - zime_alphanumeric_segmentor\n"
    abort "new segmentor missing from canonical schema" unless source.scan(line).length == 1
    filter = "    - zime_display_learning\n"
    abort "display learner missing from canonical schema" unless source.scan(filter).length == 1
    File.binwrite(path, source.sub(line, "").sub(filter, ""))
  end
' "${shared}/linnet_zh.schema.yaml" "${shared}/linnet_en.schema.yaml"
# An installed pre-0.1.8 language pack disables English learning in Chinese
# mode. Only the new Core projection may repair that retained pack.
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  current = "linnet_english_words:\n  dictionary: linnet_en\n  user_dict: linnet_zh_english\n  enable_completion: false\n  enable_sentence: false\n  enable_user_dict: true\n"
  stale = "linnet_english_words:\n  dictionary: linnet_en\n  enable_completion: false\n  enable_sentence: false\n  enable_user_dict: false\n"
  abort "current Chinese-mode English learner is missing" unless source.scan(current).length == 1
  File.binwrite(path, source.sub(current, stale))
' "${shared}/linnet_zh.schema.yaml"
# Core-only updates deliberately keep the installed language pack. Reproduce
# old Active owners so the native suite proves the Core projections, not a
# coincidentally current pack, retire stale routing and schema defaults.
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  placeholder = "    zz_code_token: \"^$\"\n"
  stale = "    zz_code_token: \"^(?:(?:/|~).*|(?:www[.]|https?:|ftp[.:]|mailto:|file:).*)$\"\n"
  current_shift = "    Shift_L: commit_code\n    Shift_R: commit_code\n"
  stale_shift = "    Shift_L: commit_text\n    Shift_R: commit_text\n"
  current_schemas = "  - schema: linnet_zh_pinyin\n  - schema: linnet_en\n"
  stale_schemas = "  - schema: linnet_en\n  - schema: linnet_zh_pinyin\n"
  abort "Core compile placeholder is missing" unless source.scan(placeholder).length == 1
  abort "current Shift policy is missing" unless source.scan(current_shift).length == 1
  abort "current schema order is missing" unless source.scan(current_schemas).length == 1
  File.binwrite(
    path,
    source.sub(placeholder, stale)
      .sub(current_shift, stale_shift)
      .sub(current_schemas, stale_schemas)
  )
' "${shared}/default.yaml"
cp data/linnet/linnet_algebra.yaml "${shared}/linnet_algebra.yaml"
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  current_prism = "  prism: linnet_zh_pinyin\n"
  current_return = "  chinese_schema: linnet_zh_pinyin\n"
  abort "current full-pinyin Prism is missing" unless source.scan(current_prism).length == 1
  abort "current full-pinyin return is missing" unless source.scan(current_return).length == 1
  File.binwrite(
    path,
    source.sub(current_prism, "  prism: linnet_zh\n")
      .sub(current_return, "  chinese_schema: linnet_zh\n")
  )
' "${shared}/linnet_en.schema.yaml"
cp -R data/opencc/. "${shared}/opencc/"
cp tests/fixtures/linnet_pinyin_limit.dict.yaml \
  tests/fixtures/linnet_pinyin_limit_algebra.yaml \
  tests/fixtures/linnet_pinyin_limit_64.schema.yaml \
  tests/fixtures/linnet_pinyin_limit_65.schema.yaml "${shared}/"
cp tests/fixtures/linnet_user.yaml \
  tests/fixtures/linnet_custom_words.txt \
  tests/fixtures/linnet_text_expander.txt "${user}/"
end_phase "stage isolated product data"

begin_phase "compile Settings projection fixture"
source tests/swift_test_cache.sh
linnet_swift_cache_init "${repo_root}" "${scratch}"
sdk="$(xcrun --show-sdk-path)"
linnet_swift_compile projection-fixture -warnings-as-errors -sdk "${sdk}" \
  sources/LinnetPackContract.swift \
  sources/LinnetDataChannel.swift \
  sources/LinnetDataRegistry.swift sources/LinnetDirectoryDelta.swift sources/LinnetDataRegistryTransactions.swift sources/LinnetDataRegistryStorage.swift \
  sources/LinnetSettings/SettingsContract.swift \
  sources/LinnetSettings/PersonalDataStore.swift \
  sources/LinnetSettings/PersonalDataValidation.swift \
  sources/LinnetSettings/LinnetSettingsDocument.swift sources/LinnetSettings/LinnetSettingsDocumentStore.swift \
  sources/LinnetSettings/LinnetSettingsProjectionRenderer.swift \
  tests/LinnetSettingsProjectionFixture.swift
linnet_test_run 600 "${scratch}/projection-fixture" default "${user}"
for switch_key in Caps_Lock Shift_L Shift_R; do
  test "$(rg -F -c \
    "\"ascii_composer/switch_key/${switch_key}\": commit_code" \
    "${user}/default.custom.yaml")" -eq 1
done
test "$(rg -F -c '"linnet/recognizer_patterns/zz_code_token"' \
  "${user}/default.custom.yaml")" -eq 1
end_phase "compile Settings projection fixture"
if [[ "${runtime_probe}" == --profile-key-matrix-probe ]]; then
  # ZIME exposes full pinyin + English by default. This dedicated compatibility
  # fixture must explicitly deploy all eight inherited layouts; select_schema
  # alone can otherwise create an empty engine for an undeployed schema.
  ruby -ryaml -e '
    path = ARGV.fetch(0)
    config = YAML.load_file(path)
    ids = %w[linnet_zh_pinyin linnet_zh linnet_zh_flypy linnet_zh_mspy linnet_zh_sogou linnet_zh_abc linnet_zh_ziguang linnet_zh_jiajia linnet_en]
    config.fetch("patch").delete_if { |key, _| key.start_with?("schema_list/") }
    config.fetch("patch")["schema_list"] = ids.map { |id| {"schema" => id} }
    File.write(path, YAML.dump(config))
  ' "${user}/default.custom.yaml"
fi

compile_compatibility_schemas() {
  for profile in linnet_zh linnet_zh_flypy linnet_zh_mspy linnet_zh_sogou linnet_zh_abc linnet_zh_ziguang linnet_zh_jiajia; do
    DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
      linnet_test_run 600 bin/rime_deployer --compile "${shared}/${profile}.schema.yaml" \
        "${user}" "${shared}" "${user}/build" >/dev/null
  done
}

begin_phase "deploy native schemas"
make --no-print-directory smart-english-plugin
make --no-print-directory verify-rime-binaries
if [[ "${runtime_probe}" == --zime-case-probe ]]; then
  /usr/bin/ruby tests/verify_zime_case_aliases.rb
fi
RIME_LOG_DIR="${logs}" \
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
if [[ -z "${runtime_probe}" || "${runtime_probe}" == --mixed-input-probe ||
      "${runtime_probe}" == --fast-config-reload-probe ]]; then
  # The legacy mixed matrix directly selects inherited profiles. Compile
  # those test-only schemas without changing the product's two-schema list.
  compile_compatibility_schemas
fi
for fixture_schema in \
  linnet_pinyin_limit_64.schema.yaml \
  linnet_pinyin_limit_65.schema.yaml; do
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 bin/rime_deployer --compile "${shared}/${fixture_schema}" \
      "${user}" "${shared}" "${user}/build" >/dev/null
done
end_phase "deploy native schemas"

begin_phase "compile native smoke harnesses"
cxx="$(xcrun --find clang++)"
ruby tests/cxx_test_cache.rb "${repo_root}/build/cxx-test-cache" "${scratch}/rime-smoke" -- \
  "${cxx}" -isysroot "${sdk}" -std=c++17 -O2 -Wall -Wextra -Werror \
  -DGLOG_USE_GLOG_EXPORT -isystem librime/dist/include \
  -isystem build/dependencies/boost tests/rime_smoke_test.cc \
  plugins/smart_english/smart_english_index.cc \
  lib/librime.1.dylib lib/rime-plugins/librime-lua.dylib \
  lib/rime-plugins/librime-predict.dylib

# Reuse the canonical Chinese learning probe only where the mixed-input matrix
# consumes it. The learned phrase is written later to an isolated user root so
# it cannot perturb the general candidate-ranking matrix above.
if [[ -z "${runtime_probe}" || "${runtime_probe}" == --mixed-input-probe ]]; then
  ruby tests/cxx_test_cache.rb "${repo_root}/build/cxx-test-cache" "${scratch}/auto-phrase-probe" -- \
    "${cxx}" -isysroot "${sdk}" -std=c++17 -O2 -Wall -Wextra -Werror \
    -isystem librime/dist/include tests/auto_phrase_probe.cc \
    lib/librime.1.dylib lib/rime-plugins/librime-lua.dylib
fi
end_phase "compile native smoke harnesses"

begin_phase "run native candidate matrix"
if [[ "${LINNET_KEEP_FAILED_RIME_FIXTURE:-0}" == 1 ]]; then
  cp -R "${user}" "${scratch}/pristine-user"
fi
smoke_args=("${shared}" "${user}")
if [[ -n "${runtime_probe}" ]]; then
  smoke_args+=("${runtime_probe}")
fi
if ! linnet_test_run 600 /bin/bash -o pipefail -c '
    export DYLD_LIBRARY_PATH="$1"
    error_log=$2; output_log=$3; shift 3
    "$@" 2>"$error_log" | tee "$output_log"
  ' _ "${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    "${scratch}/stderr" "${scratch}/stdout" "${scratch}/rime-smoke" "${smoke_args[@]}"; then
  tail -n 160 "${scratch}/stdout" >&2 || true
  tail -n 160 "${scratch}/stderr" >&2 || true
  exit 1
fi
end_phase "run native candidate matrix"

if [[ "${runtime_probe}" == --zime-shortcuts-probe ]]; then
  begin_phase "reopen and export/restore emoji learning"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" --zime-emoji-reopen-probe
  restored_user="${scratch}/restored-emoji-user"
  mkdir "${restored_user}"
  cp -R "${user}/build" "${restored_user}/build"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 --chdir "${user}" "${repo_root}/bin/rime_dict_manager" --export linnet_zh "${scratch}/emoji-learning.txt"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 --chdir "${restored_user}" "${repo_root}/bin/rime_dict_manager" --import linnet_zh "${scratch}/emoji-learning.txt"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${restored_user}" --zime-emoji-reopen-probe
  end_phase "reopen and export/restore emoji learning"
fi

if [[ "${runtime_probe}" == --zime-bilingual-probe ]]; then
  begin_phase "reopen learned ranking in a fresh process"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" --zime-ranking-reopen-probe
  end_phase "reopen learned ranking in a fresh process"
  begin_phase "persist English preference and honor the learning switch"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" --zime-english-ranking-reopen-probe
  linnet_test_run 600 "${scratch}/projection-fixture" zime-english-learning-off "${user}"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" --zime-english-learning-off-probe
  linnet_test_run 600 "${scratch}/projection-fixture" default "${user}"
  linnet_test_run 600 "${scratch}/projection-fixture" chinese-learning disabled "${user}"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" --zime-chinese-learning-off-probe
  linnet_test_run 600 "${scratch}/projection-fixture" default "${user}"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" --zime-english-ranking-reopen-probe
  end_phase "persist English preference and honor the learning switch"
fi

if [[ -z "${runtime_probe}" || "${runtime_probe}" == --mixed-input-probe ]]; then
  begin_phase "verify mixed-input learning policy"
  mixed_learning_on_user="${scratch}/mixed-learning-on-user"
  mkdir "${mixed_learning_on_user}"
  cp -R "${user}/." "${mixed_learning_on_user}/"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/auto-phrase-probe" "${shared}" \
      "${mixed_learning_on_user}" linnet_zh_pinyin >/dev/null \
      <<< 'learn 霜河栈 shuanghezhan 霜 河 栈'
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${mixed_learning_on_user}" \
      --mixed-learning-on-probe >/dev/null

  mixed_learning_off_user="${scratch}/mixed-learning-off-user"
  mkdir "${mixed_learning_off_user}"
  cp -R "${mixed_learning_on_user}/." "${mixed_learning_off_user}/"
  linnet_test_run 600 "${scratch}/projection-fixture" chinese-learning disabled \
    "${mixed_learning_off_user}"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 bin/rime_deployer --build "${mixed_learning_off_user}" "${shared}" \
      "${mixed_learning_off_user}/build" >/dev/null
  rg -Fq 'enable_user_dict: false' \
    "${mixed_learning_off_user}/build/linnet_zh_pinyin.schema.yaml"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${mixed_learning_off_user}" \
      --mixed-learning-off-probe >/dev/null
  end_phase "verify mixed-input learning policy"
fi

if [[ -n "${runtime_probe}" ]]; then
  if [[ "${runtime_probe}" == --mixed-latency-probe ]]; then
    echo "Linnet native Rime mixed-input latency measurement: COMPLETE"
  elif [[ "${runtime_probe}" == --warm-session-probe ]]; then
    echo "Linnet native Rime retained warm-session latency: PASS"
  elif [[ "${runtime_probe}" == --cold-client-probe ]]; then
    echo "Linnet native Rime cold-client first-key latency: PASS"
  elif [[ "${runtime_probe}" == --profile-key-matrix-probe ]]; then
    echo "Linnet native Rime formal eight-profile key matrix: PASS"
  elif [[ "${runtime_probe}" == --zime-paging-probe ]]; then
    echo "ZIME native Rime paging boundaries: PASS"
  elif [[ "${runtime_probe}" == --live-sync-probe ]]; then
    echo "Linnet native Rime live synchronization: PASS"
  else
    echo "ZIME native Rime ${runtime_probe}: PASS"
  fi
  exit 0
fi

rg -Fq 'shared PredictEngine factory/engine identity: PASS' "${scratch}/stdout"
test "$(LC_ALL=C grep -a -F -c 'loading predict db:' "${scratch}/stderr")" -eq 1

lifecycle_user="${scratch}/lifecycle-user"
mkdir "${lifecycle_user}"
cp -R "${user}/." "${lifecycle_user}/"

# Exercise librime's canonical multi-device user-dictionary merge. Linnet only
# schedules this upstream owner; it never interprets snapshot rows itself.
begin_phase "verify upstream user-dictionary sync"
sync_root="${scratch}/rime-sync"
device_a="${scratch}/device-a"
device_b="${scratch}/device-b"
mkdir "${sync_root}" "${device_a}" "${device_b}"
for dictionary in linnet_zh linnet_en; do
  test -d "${user}/${dictionary}.userdb"
  cp -R "${user}/${dictionary}.userdb" "${device_a}/${dictionary}.userdb"
  cp -R "${user}/${dictionary}.userdb" "${device_b}/${dictionary}.userdb"
done
printf 'installation_id: device-a\nsync_dir: "%s"\nbackup_config_files: false\n' \
  "${sync_root}" >"${device_a}/installation.yaml"
printf 'installation_id: device-b\nsync_dir: "%s"\nbackup_config_files: false\n' \
  "${sync_root}" >"${device_b}/installation.yaml"
printf '# Rime user dictionary export\n云同步甲\tyun tong bu jia\t7\nlinnetclouda\tlinnetclouda\t7\n' \
  >"${scratch}/device-a-rows.txt"
printf '# Rime user dictionary export\n云同步乙\tyun tong bu yi\t9\nlinnetcloudb\tlinnetcloudb\t9\n' \
  >"${scratch}/device-b-rows.txt"
for dictionary in linnet_zh linnet_en; do
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 --chdir "${device_a}" "${repo_root}/bin/rime_dict_manager" --import "${dictionary}" \
      "${scratch}/device-a-rows.txt" >/dev/null
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 --chdir "${device_b}" "${repo_root}/bin/rime_dict_manager" --import "${dictionary}" \
      "${scratch}/device-b-rows.txt" >/dev/null
done
for device in "${device_a}" "${device_b}" "${device_a}"; do
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 --chdir "${device}" "${repo_root}/bin/rime_dict_manager" --sync >/dev/null
done
for dictionary in linnet_zh linnet_en; do
  export_file="${scratch}/${dictionary}-merged.txt"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 --chdir "${device_a}" "${repo_root}/bin/rime_dict_manager" --export "${dictionary}" \
      "${export_file}" >/dev/null
  rg -Fq $'云同步甲\t' "${export_file}"
  rg -Fq $'云同步乙\t' "${export_file}"
  rg -Fq $'linnetclouda\t' "${export_file}"
  rg -Fq $'linnetcloudb\t' "${export_file}"
done
echo "Linnet upstream multi-device user dictionary sync: PASS"
live_sync_user="${scratch}/live-sync-user"
mkdir "${live_sync_user}"
cp -R "${user}/." "${live_sync_user}/"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${live_sync_user}" --live-sync-probe
end_phase "verify upstream user-dictionary sync"

# Exercise the production-shaped exact-11 configuration reload in its own
# user directory so its same-second projections and session invalidation never
# become implicit setup for the remaining Settings/runtime matrix.
begin_phase "verify legacy-profile migration and Settings projections"
fast_user="${scratch}/fast-user"
mkdir "${fast_user}"
cp -R "${user}/." "${fast_user}/"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${fast_user}" \
    --fast-config-reload-probe

profile_cases=(
  'vertical_bar:natural'
  'vertical_bar:full_pinyin'
  'vertical_bar:flypy'
  'vertical_bar:microsoft'
  'vertical_bar:sogou'
  'vertical_bar:abc'
  'vertical_bar:ziguang'
  'vertical_bar:jiajia'
  # Migrating a retired profile must preserve the independent trigger choice.
  'semicolon:microsoft'
)
for profile_case in "${profile_cases[@]}"; do
  IFS=: read -r trigger profile <<<"${profile_case}"
  linnet_test_run 600 "${scratch}/projection-fixture" profile "${profile}" "${trigger}" "${user}"
  # The production document normalizes every retained legacy profile to full
  # pinyin. Native compatibility layouts are exercised separately; do not
  # expect retired Settings choices to re-enter the public schema list.
  schema=linnet_zh_pinyin
  code=suanfa
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" \
      "${user}/build" >/dev/null
  rg -Fq "prism: ${schema}" "${user}/build/linnet_en.schema.yaml"
  rg -Fq "chinese_schema: ${schema}" "${user}/build/linnet_en.schema.yaml"
  test -s "${user}/build/${schema}.prism.bin"
  prefix=';'
  [[ "${trigger}" == vertical_bar ]] && prefix='|'
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" \
      --english-profile-probe \
        "${profile}" "${schema}" "${code}" "${prefix}" >/dev/null
done

for page_size in 3 4 5 6 7 8 9; do
  linnet_test_run 600 "${scratch}/projection-fixture" page-size "${page_size}" "${user}"
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
  DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
    linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" \
      --page-size-probe "${page_size}" >/dev/null
done

linnet_test_run 600 "${scratch}/projection-fixture" english-learning-off "${user}"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
rg -Fq 'prism: linnet_zh_pinyin' "${user}/build/linnet_en.schema.yaml"
rg -Fq 'chinese_schema: linnet_zh_pinyin' "${user}/build/linnet_en.schema.yaml"
rg -Fq 'enable_user_dict: false' "${user}/build/linnet_en.schema.yaml"
rg -Fq 'learning_enabled: false' "${user}/build/linnet_en.schema.yaml"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" \
    --learning-off-probe >/dev/null

linnet_test_run 600 "${scratch}/projection-fixture" english-suggestions-off "${user}"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
# The following native check directly selects inherited schemas too. A normal
# --build only refreshes the public schema graph; refresh these test-only
# configs after projection so the check cannot read stale compiled options.
compile_compatibility_schemas
rg -Fq 'prism: linnet_zh_pinyin' "${user}/build/linnet_en.schema.yaml"
rg -Fq 'chinese_schema: linnet_zh_pinyin' "${user}/build/linnet_en.schema.yaml"
rg -Fq 'reset: 0' "${user}/build/linnet_en.schema.yaml"
if rg -q 'spelling_correction:' "${user}/build/linnet_en.schema.yaml"; then
  echo "retired English correction switch returned to the deployed schema" >&2
  exit 1
fi
rg -Fq 'show_ipa: false' "${user}/build/linnet_en.schema.yaml"
rg -Fq 'show_translation: false' "${user}/build/linnet_en.schema.yaml"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" \
    --settings-off-probe >/dev/null

linnet_test_run 600 "${scratch}/projection-fixture" input-options "${user}"
test -s "${user}/linnet_user.custom.yaml"
test ! -e "${user}/linnet_user.yaml"
rg -Fq '    - "hello"' "${user}/linnet_user.custom.yaml"
! rg -Fq 'sentence_capitalization' "${user}/linnet_user.custom.yaml"
! rg -Fq 'tab_behavior' "${user}/linnet_user.custom.yaml"
for settings_schema in \
  linnet_zh linnet_zh_pinyin linnet_zh_flypy linnet_zh_mspy \
  linnet_zh_sogou linnet_zh_abc linnet_zh_ziguang linnet_zh_jiajia \
  linnet_en; do
  test -s "${user}/${settings_schema}.custom.yaml"
  rg -Fq '"linnet_english_interaction/sentence_capitalization": false' \
    "${user}/${settings_schema}.custom.yaml"
  rg -Fq '"linnet_english_interaction/tab_behavior": "pass"' \
    "${user}/${settings_schema}.custom.yaml"
  rg -Fq '"linnet_english_interaction/space_adds_trailing_space": false' \
    "${user}/${settings_schema}.custom.yaml"
done
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
compile_compatibility_schemas
ruby -ryaml -e '
  ARGV.each do |path|
    config = YAML.load_file(path)
    abort "traditionalization projection was not deployed: #{path}" unless
      config.fetch("switches").any? { |entry| entry["name"] == "traditionalization" && entry["reset"] == 1 }
    abort "reverse prefix projection was not deployed: #{path}" unless
      config.dig("linnet_pinyin", "prefix") == "|"
  end
' "${user}"/build/linnet_zh*.schema.yaml
rg -Fq 'prism: linnet_zh_pinyin' "${user}/build/linnet_en.schema.yaml"
rg -Fq 'chinese_schema: linnet_zh_pinyin' "${user}/build/linnet_en.schema.yaml"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" \
    --input-options-probe >/dev/null

linnet_test_run 600 "${scratch}/projection-fixture" input-switches "${user}"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 bin/rime_deployer --build "${user}" "${shared}" "${user}/build" >/dev/null
for chinese_schema in \
  linnet_zh linnet_zh_pinyin linnet_zh_flypy linnet_zh_mspy \
  linnet_zh_sogou linnet_zh_abc linnet_zh_ziguang linnet_zh_jiajia; do
  rg -Fq '"switches/@1/reset": 1' "${user}/${chinese_schema}.custom.yaml"
  rg -Fq '"switches/@3/reset": 0' "${user}/${chinese_schema}.custom.yaml"
  rg -Fq '"switches/@4/reset": 1' "${user}/${chinese_schema}.custom.yaml"
done
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${user}" \
    --input-switches-probe >/dev/null
end_phase "verify legacy-profile migration and Settings projections"

# The default matrix above owns the ordinary lifecycle rows. Reuse its staged
# data and compiled harness for the switcher-only rows instead of starting a
# second complete shell verifier and recompiling both Swift and C++ fixtures.
begin_phase "verify lifecycle exits with the F4 switcher"
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  current = "  hotkeys: []\n"
  fixture = "  hotkeys: [F4]\n"
  abort "switcher hotkey owner is missing" unless source.scan(current).length == 1
  File.binwrite(path, source.sub(current, fixture))
' "${shared}/default.yaml"
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 bin/rime_deployer --build "${lifecycle_user}" "${shared}" \
    "${lifecycle_user}/build" >/dev/null
DYLD_LIBRARY_PATH="${repo_root}/lib:${repo_root}/lib/rime-plugins" \
  linnet_test_run 600 "${scratch}/rime-smoke" "${shared}" "${lifecycle_user}" \
    --lifecycle-raw-exit-probe
end_phase "verify lifecycle exits with the F4 switcher"

echo "Linnet native Rime runtime: PASS (Chinese, 8-profile Smart English, direct Shift, Caps Lock raw, learning, graphical English and input settings)"
