#!/usr/bin/env bash

# Unified development gate. Core checks need staged dependencies/data; app/all
# additionally need a compiled local App. No signing or installation occurs.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${repo_root}"
source tests/test_runner.sh

if [[ $# -gt 1 ]]; then
  echo "Usage: tests/verify_development.sh [quick|full|release|all|core|app|swift|rime]" >&2
  exit 2
fi
profile="${1:-all}"
case "${profile}" in
  quick|full|release|all|core|app|swift|rime) ;;
  *)
    echo "Usage: tests/verify_development.sh [quick|full|release|all|core|app|swift|rime]" >&2
    exit 2
    ;;
esac

run_app=0
run_swift=0
run_rime=0
case "${profile}" in
  all|release) run_app=1; run_swift=1; run_rime=1 ;;
  core|full) run_swift=1; run_rime=1 ;;
  app) run_app=1 ;;
  swift) run_swift=1 ;;
  rime) run_rime=1 ;;
esac

if [[ "${profile}" == core || "${profile}" == full ]]; then
  linnet_test_call make --no-print-directory english-data-generator
  linnet_test_call tests/verify_english_data_projection.sh
fi

if [[ "${run_swift}" -eq 1 || "${profile}" == quick ]]; then
  linnet_test_call ruby tests/verify_coverage_gate.rb
  linnet_test_call ruby tests/verify_test_process.rb
  linnet_test_call ruby tests/verify_test_runner.rb
  linnet_test_call ruby tests/verify_test_owner_chain.rb
  linnet_test_call ruby tests/verify_runtime_mutations.rb
  linnet_test_call ruby tests/verify_compile_artifact_cache.rb
  linnet_test_call ruby tests/verify_swift_test_cache.rb
  linnet_test_call ruby tests/verify_cxx_test_cache.rb
  linnet_test_call ruby tests/verify_development_gate.rb
  linnet_test_call tests/verify_rime_test_orchestration.sh
  linnet_test_call tests/verify_publication_owner.sh
  linnet_test_call tests/verify_release_automation.sh
  linnet_test_call tests/verify_zime_installer.sh
  linnet_test_call tests/verify_zime_privacy.sh
fi

if [[ "${run_app}" -eq 1 ]]; then
  host_app="${repo_root}/build/Local/Build/Products/Release/ZIME.app"
  standalone_settings="${repo_root}/build/Local/Build/Products/Release/Settings.app"
  embedded_settings="${host_app}/Contents/Applications/Settings.app"
  for app in "${host_app}" "${standalone_settings}" "${embedded_settings}"; do
    [[ -d "${app}" && ! -L "${app}" ]] || {
      echo "verify_development: missing unsigned Release App: ${app}" >&2
      exit 1
    }
    [[ ! -e "${app}/Contents/_CodeSignature" &&
       ! -L "${app}/Contents/_CodeSignature" ]] || {
      echo "verify_development: unsigned Release retained a stale signature: ${app}" >&2
      exit 1
    }
  done

  [[ "$(plutil -extract CFBundleIdentifier raw -o - \
    "${host_app}/Contents/Info.plist")" == \
      com.zime.inputmethod.ZIME.local-build ]] || {
    echo "verify_development: local Host regained the production identity" >&2
    exit 1
  }
  for settings_app in "${standalone_settings}" "${embedded_settings}"; do
    [[ "$(plutil -extract CFBundleIdentifier raw -o - \
      "${settings_app}/Contents/Info.plist")" == \
      com.zime.inputmethod.ZIME.local-build.settings ]] || {
      echo "verify_development: local Settings regained the production identity" >&2
      exit 1
    }
  done

# A local unsigned composite has no clean candidate revision to bind. The
# successful composite build owns one completion marker after Xcode, resource
# sanitization and local-identity verification all finish.
  host_executable="${host_app}/Contents/MacOS/ZIME"
  settings_executables=(
    "${standalone_settings}/Contents/MacOS/Settings"
    "${embedded_settings}/Contents/MacOS/Settings"
  )
  for executable in "${host_executable}" "${settings_executables[@]}"; do
    [[ -f "${executable}" && ! -L "${executable}" && -x "${executable}" ]] || {
      echo "verify_development: missing Release executable: ${executable}" >&2
      exit 1
    }
  done

  build_stamp="${repo_root}/build/Local/Build/Products/Release/.linnet-build-complete"
  [[ -f "${build_stamp}" && ! -L "${build_stamp}" ]] || {
    echo "verify_development: missing successful Release build marker" >&2
    exit 1
  }

verify_inputs_predate() {
  local executable="$1"
  local input
  while IFS= read -r input; do
    [[ -f "${input}" && ! -L "${input}" ]] || {
      echo "verify_development: missing or unsafe build input: ${input}" >&2
      exit 1
    }
    [[ ! "${input}" -nt "${executable}" ]] || {
      echo "verify_development: Release is older than build input: ${input}" >&2
      exit 1
    }
  done
}

  # A process substitution does not propagate the producer's exit status.
  # Collect successfully first, so a failed git/find cannot become an empty
  # (and therefore apparently fresh) source inventory.
  build_inputs="$(
    {
      git ls-files --cached --others --exclude-standard -- \
        Makefile Linnet.xcodeproj/project.pbxproj config/LinnetProduct.xcconfig \
        sources resources data/linnet data/squirrel.yaml || exit "$?"
      find data/plum data/opencc lib -type f -print || exit "$?"
    } | LC_ALL=C sort -u
  )" || exit "$?"
  [[ -n "${build_inputs}" ]] || {
    echo "verify_development: empty build input inventory" >&2
    exit 1
  }
  verify_inputs_predate "${build_stamp}" <<< "${build_inputs}"

  # ZIME's staged ZIP/PKG transaction is not the inherited CMS installer.
  linnet_test_call tests/verify_zime_app.sh "${host_app}" local
  linnet_test_call tests/verify_visible_settings_fixture.sh --verify local
  linnet_test_call make --no-print-directory english-data-generator
  linnet_test_call tests/verify_english_data_projection.sh
  linnet_test_call ruby tests/generate_m2_fixtures.rb --check
  linnet_test_call scripts/build-privacy scan "${host_app}"
fi

if [[ "${run_swift}" -eq 1 || "${profile}" == quick ]]; then
  if [[ "${run_swift}" -eq 1 ]]; then linnet_test_call tests/verify_swift_units.sh; fi
  linnet_test_call bash tests/verify_zime.sh
  linnet_test_call bash tests/verify_zime_translation.sh
  if [[ "${run_swift}" -eq 1 ]]; then linnet_test_call ruby tests/verify_candidate_translation_mutations.rb; fi
fi

if [[ "${run_rime}" -eq 1 ]]; then
  if [[ "${run_swift}" -eq 0 ]]; then linnet_test_call tests/verify_rime_test_orchestration.sh; fi
  linnet_test_call tests/verify_lua_lifetime.sh
  linnet_test_call tests/verify_data_release_baseline.sh
  linnet_test_call tests/verify_chinese_upstream_workflow.sh
  linnet_test_call ruby scripts/upstream-sync verify
  linnet_test_call tests/verify_chinese_source_projection.sh
  linnet_test_call tests/verify_locked_release_asset.sh
  linnet_test_call tests/verify_chinese_grammar.sh
  linnet_test_call ruby tests/verify_profile_golden.rb
  linnet_test_call tests/verify_chinese_learning_policy.sh
  linnet_test_call tests/verify_rime_runtime.sh
  # The default matrix already owns ExpectAlphanumericComposition. Keep its
  # focused CLI for diagnosis, but do not repeat it in the full gate.
  for probe in --zime-shortcuts-probe --zime-bilingual-probe --zime-case-probe --zime-paging-probe --profile-key-matrix-probe --zime-soak-probe; do
    linnet_test_call tests/verify_rime_runtime.sh "${probe}"
  done
fi

if [[ "${profile}" == release ]]; then
  linnet_test_call swiftlint lint --strict --config .swiftlint.yml
  linnet_test_call scripts/run_periphery.sh
  linnet_test_call tests/verify_zime_coverage.sh
fi

echo "ZIME development gate (${profile}): PASS (no signing or installation; real UI/API/manual acceptance not included)"
