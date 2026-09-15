#!/usr/bin/env bash
# Compatibility tombstone: never report a historical test as a current PASS.
echo "ARCHIVED: verify_product.sh does not apply to ZIME; use tests/verify_development.sh core or release. See tests/legacy/README.md." >&2
exit 64
