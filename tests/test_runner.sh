#!/usr/bin/env bash
# Source in standalone test owners. Keep their EXIT trap; cancellation waits
# for runtime teardown before that trap is allowed to remove fixture files.
LINNET_TEST_RUNNER_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/run_test_process.rb"
LINNET_TEST_RUNNER_PID=''

linnet_test_cancel() {
  local signal="$1" result="$2"
  trap '' INT TERM HUP
  if [[ -n "${LINNET_TEST_RUNNER_PID}" ]]; then
    kill -"${signal}" "${LINNET_TEST_RUNNER_PID}" 2>/dev/null || true
    wait "${LINNET_TEST_RUNNER_PID}" 2>/dev/null || true
  fi
  exit "${result}"
}

linnet_test_runner_init() {
  trap 'linnet_test_cancel INT 130' INT
  trap 'linnet_test_cancel TERM 143' TERM
  trap 'linnet_test_cancel HUP 129' HUP
}

linnet_test_run() {
  local result=0
  # Explicit stdin inheritance: non-interactive Bash otherwise substitutes
  # /dev/null for background commands. wait makes Bash handle signals now,
  # instead of deferring them until a foreground executable has exited.
  LINNET_TEST_LOADER_RELAY=1 \
    LINNET_TEST_DYLD_LIBRARY_PATH_SET="${DYLD_LIBRARY_PATH+x}" \
    LINNET_TEST_DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH-}" \
    LINNET_TEST_DYLD_FALLBACK_LIBRARY_PATH_SET="${DYLD_FALLBACK_LIBRARY_PATH+x}" \
    LINNET_TEST_DYLD_FALLBACK_LIBRARY_PATH="${DYLD_FALLBACK_LIBRARY_PATH-}" \
    ruby "${LINNET_TEST_RUNNER_SCRIPT}" "$@" <&0 &
  LINNET_TEST_RUNNER_PID=$!
  wait "${LINNET_TEST_RUNNER_PID}" || result=$?
  LINNET_TEST_RUNNER_PID=''
  return "${result}"
}

linnet_test_runner_init
