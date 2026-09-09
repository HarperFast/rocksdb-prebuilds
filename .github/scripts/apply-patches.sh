#!/usr/bin/env bash
# Apply the official vcpkg patches, then the named experimental patch directories,
# to a RocksDB source tree.
#
# Shared by the release build, the PR gate and the nightly audit. If a gate applied
# a different stack than the build ships, it would be proving the wrong thing --
# the same reason id canonicalization lives in experimental-ids.sh.
#
# usage: apply-patches.sh ROCKSDB_SOURCE_DIR [EXPERIMENTAL_DIR_NAME...]
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 ROCKSDB_SOURCE_DIR [EXPERIMENTAL_DIR_NAME...]" >&2
  exit 2
fi

src="$(cd "$1" && pwd)"
shift
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# -F0 (zero fuzz): a patch whose context drifted in a newer RocksDB fails loudly
# instead of fuzzy-matching a hunk into a plausible but wrong site.
for patch_file in vcpkg-overlays/rocksdb/patches/*.patch; do
  [ -f "$patch_file" ] || continue
  echo "Applying official patch: $patch_file"
  patch -p1 -F0 -d "$src" < "$patch_file"
done

for name in "$@"; do
  dir="experimental-patches/${name#experimental-patches/}"
  dir="${dir%/}"
  applied=0
  # Within a directory, LC_ALL=C order so every runner applies the same sequence.
  while IFS= read -r patch_file; do
    [ -f "$patch_file" ] || continue
    echo "Applying experimental patch: $patch_file"
    patch -p1 -F0 -d "$src" < "$patch_file"
    applied=$((applied + 1))
  done < <(printf '%s\n' "$dir"/*.patch | LC_ALL=C sort)

  if [[ "$applied" -eq 0 ]]; then
    echo "$dir contains no .patch file" >&2
    exit 1
  fi
done
