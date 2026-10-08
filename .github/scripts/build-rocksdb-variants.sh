#!/usr/bin/env bash
# Build the two published RocksDB variants and stage them into one dist tree.
#
# The glibc/macOS/Windows job and the musl container job both call this, so the two variants cannot
# drift between build paths the way two copies of the invocation would.
#
# Required environment:
#   WORKSPACE      directory holding dist/ (created here if missing)
#   VCPKG_ROOT     vcpkg checkout, already bootstrapped
#   VCPKG_CMD      vcpkg executable
#   VCPKG_TRIPLET  triplet to build
#   ROCKSDB_DIR    patched RocksDB source (read by the overlay portfile)
#
# Optional environment:
#   VCPKG_INSTALL_EXTRA_ARGS  whitespace-separated extra flags for both `vcpkg install` calls
set -euo pipefail

: "${WORKSPACE:?}" "${VCPKG_ROOT:?}" "${VCPKG_CMD:?}" "${VCPKG_TRIPLET:?}" "${ROCKSDB_DIR:?}"

read -ra EXTRA_VCPKG_ARGS <<< "${VCPKG_INSTALL_EXTRA_ARGS:-}" || true

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

# The enabled variant is what `vcpkg install rocksdb` has always produced, and it stays at the
# historical dist/lib path. Install it first so the second install can reuse its dependency builds.
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

# Replacing rocksdb in place rather than installing into a second root: the dependency builds this
# run already produced stay installed and are not rebuilt, and dist/ above is now the only copy of
# the enabled tree, which is what the header comparison below needs.
echo "=== Installing RocksDB (PerfContext disabled) ==="
install_rocksdb "rocksdb[${VARIANT_SUBDIR}]" --recurse

# Only worth shipping one copy of the headers if the variants really do agree on them; a future
# RocksDB that generated a variant-dependent header would otherwise ship the wrong one silently.
echo "=== Comparing installed public headers ==="
if ! diff -r "${DIST}/include" "${INSTALLED}/include"; then
  echo "Installed public headers differ between the PerfContext variants; they cannot share one copy" >&2
  exit 1
fi
echo "Public headers are identical between variants"

mkdir -p "${DIST}/lib/${VARIANT_SUBDIR}"
cp "${INSTALLED}/lib/${LIB_NAME}" "${DIST}/lib/${VARIANT_SUBDIR}/${LIB_NAME}"
readonly DISABLED_LIB="${DIST}/lib/${VARIANT_SUBDIR}/${LIB_NAME}"

# Fail before an archive exists rather than publishing a pair that is secretly one library twice:
# a binary-cache hit on the second install, or a staging copy from the wrong source, both land here.
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
