#!/usr/bin/env bash
# Source in standalone test owners. Keep their EXIT trap; cancellation waits
# for runtime teardown before that trap is allowed to remove fixture files.
LINNET_TEST_RUNNER_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/run_test_process.rb"
LINNET_TEST_OWNER_SCRIPT="${LINNET_TEST_RUNNER_SCRIPT%/*}/exec_test_owner.rb"
LINNET_TEST_RUNNER_PID=''
LINNET_TEST_RUNNER_LAUNCHING=0
LINNET_TEST_RUNNER_CANCEL=''
LINNET_TEST_RUNNER_CANCEL_STATUS=''

linnet_test_cancel() {
  local signal="$1" result="$2"
  # Bash may deliver a trap between starting a background command and storing
  # $!. Register the child before acting, otherwise cancellation can orphan it.
  if [[ "${LINNET_TEST_RUNNER_LAUNCHING}" -eq 1 ]]; then
    if [[ -z "${LINNET_TEST_RUNNER_CANCEL}" ]]; then
      LINNET_TEST_RUNNER_CANCEL="${signal}"
      LINNET_TEST_RUNNER_CANCEL_STATUS="${result}"
    fi
    return
  fi
  trap '' INT TERM HUP
  if [[ -n "${LINNET_TEST_RUNNER_PID}" ]]; then
    # Cooperative script owners forward cancellation to their own groups and
    # reap them before EXIT cleanup. Do not put another short KILL deadline
    # around them. Before bootstrap creates its group, terminate only its PID.
    kill -"${signal}" -- "-${LINNET_TEST_RUNNER_PID}" 2>/dev/null || \
      kill -TERM "${LINNET_TEST_RUNNER_PID}" 2>/dev/null || true
    wait "${LINNET_TEST_RUNNER_PID}" 2>/dev/null || true
  fi
  exit "${result}"
}

linnet_test_runner_init() {
  trap 'linnet_test_cancel INT 130' INT
  trap 'linnet_test_cancel TERM 143' TERM
  trap 'linnet_test_cancel HUP 129' HUP
}

linnet_test_call() {
  local result=0
  # Explicit stdin inheritance: non-interactive Bash otherwise substitutes
  # /dev/null for background commands. wait makes Bash handle signals now,
  # instead of deferring them until a foreground executable has exited.
  LINNET_TEST_RUNNER_LAUNCHING=1
  /usr/bin/ruby "${LINNET_TEST_OWNER_SCRIPT}" "$@" <&0 &
  LINNET_TEST_RUNNER_PID=$!
  LINNET_TEST_RUNNER_LAUNCHING=0
  if [[ -n "${LINNET_TEST_RUNNER_CANCEL}" ]]; then
    linnet_test_cancel "${LINNET_TEST_RUNNER_CANCEL}" "${LINNET_TEST_RUNNER_CANCEL_STATUS}"
  fi
  wait "${LINNET_TEST_RUNNER_PID}" || result=$?
  LINNET_TEST_RUNNER_PID=''
  return "${result}"
}

linnet_test_run() {
  LINNET_TEST_LOADER_RELAY=1 \
    LINNET_TEST_DYLD_LIBRARY_PATH_SET="${DYLD_LIBRARY_PATH+x}" \
    LINNET_TEST_DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH-}" \
    LINNET_TEST_DYLD_FALLBACK_LIBRARY_PATH_SET="${DYLD_FALLBACK_LIBRARY_PATH+x}" \
    LINNET_TEST_DYLD_FALLBACK_LIBRARY_PATH="${DYLD_FALLBACK_LIBRARY_PATH-}" \
    linnet_test_call ruby "${LINNET_TEST_RUNNER_SCRIPT}" "$@"
}

linnet_test_runner_init
