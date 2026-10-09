#!/usr/bin/env bash
# Build the two published RocksDB variants and stage them into one dist tree.
#
# Called by both the glibc/macOS/Windows job and the musl container job.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: VCPKG_TRIPLET=<triplet> ROCKSDB_DIR=<path> .github/scripts/build-rocksdb-variants.sh

Builds the PerfContext-enabled and PerfContext-disabled RocksDB libraries from one portfile and
stages both into <WORKSPACE>/dist.

Required:
  VCPKG_TRIPLET             triplet to build, e.g. arm64-osx-static
  ROCKSDB_DIR               patched RocksDB source, read by the overlay portfile

Optional (derived from this script's location when unset):
  WORKSPACE                 repository root; holds vcpkg-overlays/, vcpkg-triplets/ and dist/
  VCPKG_ROOT                $WORKSPACE/vcpkg, already bootstrapped
  VCPKG_CMD                 $VCPKG_ROOT/vcpkg[.exe]
  VCPKG_INSTALL_EXTRA_ARGS  whitespace-separated extra flags for both `vcpkg install` calls
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${WORKSPACE:=$(cd "${script_dir}/../.." && pwd)}"
: "${VCPKG_ROOT:=${WORKSPACE}/vcpkg}"
if [[ -z "${VCPKG_CMD:-}" ]]; then
  if [[ -x "${VCPKG_ROOT}/vcpkg.exe" ]]; then
    VCPKG_CMD="${VCPKG_ROOT}/vcpkg.exe"
  else
    VCPKG_CMD="${VCPKG_ROOT}/vcpkg"
  fi
fi

missing=""
for required in VCPKG_TRIPLET ROCKSDB_DIR; do
  [[ -n "${!required:-}" ]] || missing="${missing:+$missing }$required"
done
if [[ -n "$missing" ]]; then
  echo "build-rocksdb-variants.sh: missing required environment: $missing" >&2
  echo >&2
  usage
  exit 2
fi
if [[ ! -x "$VCPKG_CMD" ]]; then
  echo "build-rocksdb-variants.sh: no bootstrapped vcpkg at $VCPKG_CMD; set VCPKG_CMD or bootstrap ${VCPKG_ROOT}" >&2
  exit 2
fi
if [[ ! -d "$ROCKSDB_DIR" ]]; then
  echo "build-rocksdb-variants.sh: ROCKSDB_DIR is not a directory: $ROCKSDB_DIR" >&2
  exit 2
fi

read -ra EXTRA_VCPKG_ARGS <<< "${VCPKG_INSTALL_EXTRA_ARGS:-}" || true

# vcpkg forks a telemetry uploader as it exits, and that child inherits the lock on the installed
# tree, which the next vcpkg reports as another vcpkg running rather than waiting for.
export VCPKG_DISABLE_METRICS=1

readonly INSTALLED="${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}"
readonly DIST="${WORKSPACE}/dist"
readonly VARIANT_SUBDIR="no-perf-context"

dump_logs() {
  echo '=== Build failed, dumping logs ==='
  for log in \
    "${VCPKG_ROOT}/buildtrees/detect_compiler/config-${VCPKG_TRIPLET}-out.log" \
    "${VCPKG_ROOT}/buildtrees/detect_compiler/config-${VCPKG_TRIPLET}-rel-CMakeCache.txt.log" \
    "${VCPKG_ROOT}/buildtrees/rocksdb/config-${VCPKG_TRIPLET}-out.log" \
    "${VCPKG_ROOT}/buildtrees/rocksdb/config-${VCPKG_TRIPLET}-err.log" \
    "${VCPKG_ROOT}/buildtrees/rocksdb/install-${VCPKG_TRIPLET}-dbg-out.log" \
    "${VCPKG_ROOT}/buildtrees/rocksdb/install-${VCPKG_TRIPLET}-dbg-err.log"; do
    echo "=== ${log#"${VCPKG_ROOT}/"} ==="
    cat "$log" 2>/dev/null || echo 'Log file not found'
  done
}

install_rocksdb() {
  local spec="$1"
  shift
  if ! "$VCPKG_CMD" install "$spec" \
    "$@" \
    ${EXTRA_VCPKG_ARGS[@]+"${EXTRA_VCPKG_ARGS[@]}"} \
    --triplet "$VCPKG_TRIPLET" \
    --overlay-ports="${WORKSPACE}/vcpkg-overlays" \
    --overlay-triplets="${WORKSPACE}/vcpkg-triplets"; then
    dump_logs
    exit 1
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# vcpkg treats an installed superset as satisfying the request, so `install rocksdb` against a tree
# that already holds rocksdb[no-perf-context] is a no-op and would stage the disabled library at the
# enabled path. CI clones vcpkg per job and never sees that; a re-run or a warm tree does.
# A fresh tree has nothing to remove, so ask disk rather than spend a vcpkg invocation saying so.
# find takes the directory as an operand; a glob reads a Windows VCPKG_ROOT's backslashes as escapes.
installed_rocksdb="$(find "${VCPKG_ROOT}/installed/vcpkg/info" -maxdepth 1 \
  -name "rocksdb_*_${VCPKG_TRIPLET}.list" 2>/dev/null || true)"
if [[ -n "$installed_rocksdb" ]]; then
  echo "=== Removing previously installed RocksDB ==="
  "$VCPKG_CMD" remove rocksdb \
    --triplet "$VCPKG_TRIPLET" \
    --overlay-ports="${WORKSPACE}/vcpkg-overlays" \
    --overlay-triplets="${WORKSPACE}/vcpkg-triplets" || true
else
  echo "=== No previously installed RocksDB to remove ==="
fi

# Enabled first: its dependency builds are what the second install reuses instead of rebuilding.
echo "=== Installing RocksDB (PerfContext enabled) ==="
install_rocksdb rocksdb

mkdir -p "$DIST"
cp -r "${INSTALLED}"/* "${DIST}/"

if [[ -f "${DIST}/lib/librocksdb.a" ]]; then
  readonly LIB_NAME="librocksdb.a"
elif [[ -f "${DIST}/lib/rocksdb.lib" ]]; then
  readonly LIB_NAME="rocksdb.lib"
else
  echo "No RocksDB static library in ${DIST}/lib" >&2
  ls -la "${DIST}/lib" >&2 || true
  exit 1
fi
readonly ENABLED_LIB="${DIST}/lib/${LIB_NAME}"
ENABLED_SHA="$(sha256 "$ENABLED_LIB")"
readonly ENABLED_SHA

# In place: the dependencies stay installed, and dist/ stays the only copy of the enabled tree.
echo "=== Installing RocksDB (PerfContext disabled) ==="
install_rocksdb "rocksdb[${VARIANT_SUBDIR}]" --recurse

# One shipped copy of the headers is only correct while the variants agree on them.
echo "=== Comparing installed public headers ==="
if ! diff -r "${DIST}/include" "${INSTALLED}/include"; then
  echo "Installed public headers differ between the PerfContext variants; they cannot share one copy" >&2
  exit 1
fi
echo "Public headers are identical between variants"

mkdir -p "${DIST}/lib/${VARIANT_SUBDIR}"
cp "${INSTALLED}/lib/${LIB_NAME}" "${DIST}/lib/${VARIANT_SUBDIR}/${LIB_NAME}"
readonly DISABLED_LIB="${DIST}/lib/${VARIANT_SUBDIR}/${LIB_NAME}"

# A binary-cache hit on the second install, or a staging copy from the wrong source, both end as
# one library shipped twice.
for lib in "$ENABLED_LIB" "$DISABLED_LIB"; do
  if [[ ! -f "$lib" ]]; then
    echo "Expected a regular file at $lib" >&2
    exit 1
  fi
done
if [[ "$(sha256 "$ENABLED_LIB")" != "$ENABLED_SHA" ]]; then
  echo "The staged PerfContext-enabled library changed after the second install" >&2
  exit 1
fi
if [[ "$(sha256 "$DISABLED_LIB")" == "$ENABLED_SHA" ]]; then
  echo "Both staged libraries have the same contents; the second build did not produce a distinct variant" >&2
  exit 1
fi

echo "Staged lib/${LIB_NAME} (PerfContext enabled) and lib/${VARIANT_SUBDIR}/${LIB_NAME} (PerfContext disabled)"
ls -la "${DIST}/lib/${LIB_NAME}" "${DIST}/lib/${VARIANT_SUBDIR}/${LIB_NAME}"
