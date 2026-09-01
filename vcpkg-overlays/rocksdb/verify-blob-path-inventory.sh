#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 ROCKSDB_SOURCE_DIR" >&2
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

diff -u "$script_dir/blob-path-inventory.txt" "$actual_inventory"

rg -n --no-heading 'cf_paths\.front\(\)\.path' . \
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

diff -u "$script_dir/cf-blob-path-inventory.txt" \
  "$actual_cf_path_inventory"
grep -Eq '^#define ROCKSDB_HAS_CF_BLOB_DIR 2$' \
  include/rocksdb/advanced_options.h
