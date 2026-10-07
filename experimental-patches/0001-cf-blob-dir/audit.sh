#!/usr/bin/env bash
# Cheap hook (see ../README.md): audits the patched tree for blob-path sites the
# patch must cover.
set -euo pipefail
# Call by path rather than cd-ing, so a relative source dir stays valid.
exec "$(dirname "${BASH_SOURCE[0]}")/verify-blob-path-inventory.sh" "$@"
