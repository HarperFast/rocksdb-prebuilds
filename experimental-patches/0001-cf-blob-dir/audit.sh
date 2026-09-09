#!/usr/bin/env bash
# Cheap verification hook: run on every PR *and* nightly against the release being
# built, so upstream adding a new blob-path derivation site is caught early.
# Receives the already-patched RocksDB source tree.
set -euo pipefail
# Call by path rather than cd-ing, so a relative source dir stays valid.
exec "$(dirname "${BASH_SOURCE[0]}")/verify-blob-path-inventory.sh" "$@"
