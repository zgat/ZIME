#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
product_id="$(sed -n 's/^LINNET_BUNDLE_IDENTIFIER = //p' "${repo_root}/config/LinnetProduct.xcconfig")"
[[ "${product_id}" == com.zime.inputmethod.ZIME ]] || {
  echo "unsupported current product identity: ${product_id}; historical CMS checks are archived" >&2
  exit 1
}
exec ruby "${repo_root}/tests/verify_zime_publication.rb" "$@"
