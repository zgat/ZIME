#!/usr/bin/env bash
# Compatibility alias. The unified gate executes this owner only once through
# verify_zime_translation.sh; no source-spelling assertions remain.
set -euo pipefail
exec bash "$(dirname "$0")/verify_zime_host_routing.sh" "$@"
