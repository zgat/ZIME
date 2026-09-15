#!/usr/bin/env bash

# Content-addressed compiler boundary for standalone Swift owner tests.
# Cached binaries are acceleration only: every invocation still executes the test.

linnet_swift_cache_init() {
  LINNET_SWIFT_CACHE_REPO="$1"
  LINNET_SWIFT_CACHE_SCRATCH="$2"
  LINNET_SWIFT_COMPILER="$(xcrun --find swiftc)"
  LINNET_MACOS_SDK="$(xcrun --show-sdk-path)"
  LINNET_SWIFT_CACHE_ROOT="${LINNET_SWIFT_UNIT_CACHE_ROOT:-${LINNET_SWIFT_CACHE_REPO}/build/swift-unit-cache}"
  # Keep SDK modules in the workspace too: a writable executable cache alone
  # does not stop Swift/Clang from writing into a sandboxed home directory.
  export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${LINNET_SWIFT_CACHE_REPO}/build/test-module-cache}"
  export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-${CLANG_MODULE_CACHE_PATH}}"
  mkdir -p "${LINNET_SWIFT_CACHE_SCRATCH}" "${LINNET_SWIFT_CACHE_ROOT}"
  [[ -d "${LINNET_SWIFT_CACHE_ROOT}" && ! -L "${LINNET_SWIFT_CACHE_ROOT}" ]] || {
    echo "Swift test cache root is unsafe: ${LINNET_SWIFT_CACHE_ROOT}" >&2
    return 1
  }

  LINNET_SWIFT_ENVIRONMENT_FINGERPRINT="$({
    "${LINNET_SWIFT_COMPILER}" -version 2>&1
    xcodebuild -version
    printf 'sdk=%s\n' "${LINNET_MACOS_SDK}"
    for library in \
        "${LINNET_MACOS_SDK}/SDKSettings.json" \
        "${LINNET_SWIFT_CACHE_REPO}/tests/swift_test_cache.sh"; do
      [[ -f "${library}" && ! -L "${library}" ]] && shasum -a 256 "${library}"
    done
  } | shasum -a 256 | awk '{print $1}')"
}

linnet_swift_compile() {
  local name="$1"
  shift
  [[ "${name}" =~ ^[a-z0-9-]+$ ]] || {
    echo "Invalid Swift test cache name: ${name}" >&2
    return 1
  }

  local output="${LINNET_SWIFT_CACHE_SCRATCH}/${name}"
  ruby "${LINNET_SWIFT_CACHE_REPO}/tests/swift_test_cache.rb" \
    "${LINNET_SWIFT_CACHE_REPO}" "${LINNET_SWIFT_CACHE_ROOT}" "${output}" \
    "${LINNET_SWIFT_ENVIRONMENT_FINGERPRINT}" -- \
    "${LINNET_SWIFT_COMPILER}" "$@" -module-cache-path "${SWIFT_MODULECACHE_PATH}" || return $?
  LINNET_SWIFT_COMPILED_BINARY="${output}"
}
