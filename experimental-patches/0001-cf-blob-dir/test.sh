#!/usr/bin/env bash
# Expensive hook (see ../README.md): builds and runs the upstream tests covering blob_dir.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 ROCKSDB_SOURCE_DIR" >&2
  exit 2
fi

cd "$1"
num_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
make -j"$num_cores" db_basic_test db_flush_test checkpoint_test \
  backup_engine_test options_test options_settable_test

./db_basic_test \
  --gtest_filter='*PortableLiveFileCapture*:*RecoveryBlobDirSyncedBeforeFreshManifestPublish*'
./db_flush_test \
  --gtest_filter='*BlobDirIsFsyncedForOrdinaryAndAtomicFlush*'
./checkpoint_test
./backup_engine_test
./options_test
./options_settable_test
