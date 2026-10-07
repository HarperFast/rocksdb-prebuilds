#!/usr/bin/env bash

set -euo pipefail

update_inventory=false
if [[ ${1:-} == "--update" ]]; then
  update_inventory=true
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "usage: $0 [--update] ROCKSDB_SOURCE_DIR" >&2
  exit 2
fi

source_dir=$1
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
actual_inventory=$(mktemp)
actual_cf_path_inventory=$(mktemp)
trap 'rm -f "$actual_inventory" "$actual_cf_path_inventory"' EXIT

cd "$source_dir"
rg -n --no-heading 'BlobFileName\(' . \
  -g '*.{cc,h}' \
  -g '!**/*test*' \
  -g '!utilities/blob_db/**' \
  -g '!tools/**' \
  -g '!examples/**' \
  -g '!java/**' \
  -g '!docs/**' \
  -g '!build_tools/**' \
  -g '!third-party/**' \
  -g '!fuzz/**' \
  -g '!db_stress_tool/**' \
  -g '!db_bench_tool/**' \
  | sed 's#^\./##' \
  | sort > "$actual_inventory"

rg -n --no-heading 'cf_paths(\.front\(\)|\[0\])\.path' . \
  -g '*.{cc,h}' \
  -g '!**/*test*' \
  -g '!utilities/blob_db/**' \
  -g '!tools/**' \
  -g '!examples/**' \
  -g '!java/**' \
  -g '!docs/**' \
  -g '!build_tools/**' \
  -g '!third-party/**' \
  -g '!fuzz/**' \
  -g '!db_stress_tool/**' \
  -g '!db_bench_tool/**' \
  | sed 's#^\./##' \
  | sort > "$actual_cf_path_inventory"

if [[ $update_inventory == true ]]; then
  cp "$actual_inventory" "$script_dir/blob-path-inventory.txt"
  cp "$actual_cf_path_inventory" "$script_dir/cf-blob-path-inventory.txt"
  echo "Updated blob path inventories from $source_dir"
fi

diff -u "$script_dir/blob-path-inventory.txt" "$actual_inventory"
diff -u "$script_dir/cf-blob-path-inventory.txt" \
  "$actual_cf_path_inventory"
grep -Eq '^#define ROCKSDB_HAS_CF_BLOB_DIR 2$' \
  include/rocksdb/advanced_options.h
