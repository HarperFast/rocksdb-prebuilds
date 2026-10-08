#!/usr/bin/env bash
# Verify a finished release archive, from a fresh extraction of the archive itself.
#
# Everything earlier in the job inspects build and staging trees. This runs against the bytes a
# consumer downloads, so a packaging mistake between `cp` and `tar` cannot pass.
#
# Required environment:
#   ARCHIVE     the .tar.xz to verify
#   SCRATCH     empty working directory for the extraction and probe build
#   PROBE_DIR   checkout path of tools/perf-context-probe
#   RUN_PROBE   true to compile and run the probe; false for a cross-compiled target
#
# Optional environment:
#   PROBE_CMAKE_ARGS  whitespace-separated extra CMake arguments (MSVC runtime selection)
set -euo pipefail

: "${ARCHIVE:?}" "${SCRATCH:?}" "${PROBE_DIR:?}" "${RUN_PROBE:?}"

readonly VARIANT_SUBDIR="no-perf-context"
readonly PREFIX="${SCRATCH}/extracted"

read -ra EXTRA_CMAKE_ARGS <<< "${PROBE_CMAKE_ARGS:-}" || true

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

mkdir -p "$PREFIX"
# Decompressed through xz rather than `tar -xf`: the archive is written with the same pair, so this
# needs nothing from tar that the packaging step did not already need.
xz -dc "$ARCHIVE" | tar -x -C "$PREFIX"

if [[ -f "${PREFIX}/lib/librocksdb.a" ]]; then
  readonly LIB_NAME="librocksdb.a"
elif [[ -f "${PREFIX}/lib/rocksdb.lib" ]]; then
  readonly LIB_NAME="rocksdb.lib"
else
  echo "::error::Archive has no RocksDB static library at lib/" >&2
  exit 1
fi
readonly ENABLED_LIB="${PREFIX}/lib/${LIB_NAME}"
readonly DISABLED_LIB="${PREFIX}/lib/${VARIANT_SUBDIR}/${LIB_NAME}"

echo "=== Archive layout ==="
if [[ ! -f "$DISABLED_LIB" ]]; then
  echo "::error::Archive has no PerfContext-disabled library at lib/${VARIANT_SUBDIR}/${LIB_NAME}" >&2
  exit 1
fi
if [[ "$(sha256 "$ENABLED_LIB")" == "$(sha256 "$DISABLED_LIB")" ]]; then
  echo "::error::Both archived libraries are identical; the archive does not contain two variants" >&2
  exit 1
fi
if [[ ! -f "${PREFIX}/include/rocksdb/db.h" ]]; then
  echo "::error::Archive has no public headers at include/rocksdb" >&2
  exit 1
fi
# One file only: the variant directory exists to hold a library, not a second copy of the tree.
VARIANT_ENTRIES="$(find "${PREFIX}/lib/${VARIANT_SUBDIR}" -mindepth 1 | wc -l | tr -d '[:space:]')"
readonly VARIANT_ENTRIES
if [[ "$VARIANT_ENTRIES" != "1" ]]; then
  echo "::error::lib/${VARIANT_SUBDIR} holds $VARIANT_ENTRIES entries; expected only ${LIB_NAME}" >&2
  find "${PREFIX}/lib/${VARIANT_SUBDIR}" -mindepth 1 >&2
  exit 1
fi
echo "lib/${LIB_NAME} and lib/${VARIANT_SUBDIR}/${LIB_NAME} are both present and distinct"

if [[ "$LIB_NAME" == "librocksdb.a" ]]; then
  echo "=== PerfContext symbol references ==="
  # Asserted in both directions: a one-sided check still passes if the two libraries are swapped.
  perf_context_refs() {
    nm -A "$1" 2>/dev/null |
      grep -cE ' U _{1,2}Z(TW|TH)?N7rocksdb12perf_contextE$' || true
  }
  enabled_refs="$(perf_context_refs "$ENABLED_LIB")"
  disabled_refs="$(perf_context_refs "$DISABLED_LIB")"
  echo "lib/${LIB_NAME}: $enabled_refs references; lib/${VARIANT_SUBDIR}/${LIB_NAME}: $disabled_refs references"
  if [[ "$enabled_refs" -eq 0 ]]; then
    echo "::error::lib/${LIB_NAME} has no rocksdb::perf_context references; the default path is not the PerfContext-enabled library" >&2
    exit 1
  fi
  if [[ "$disabled_refs" -ne 0 ]]; then
    echo "::error::lib/${VARIANT_SUBDIR}/${LIB_NAME} has $disabled_refs rocksdb::perf_context references; WITH_PERF_CONTEXT=OFF did not apply" >&2
    exit 1
  fi
fi

if [[ "$RUN_PROBE" != "true" ]]; then
  echo "::notice::Behavioural probe skipped: this target is cross-compiled and its binaries cannot run on this runner"
  exit 0
fi

echo "=== Behavioural probe ==="
run_probe() {
  local name="$1" expectation="$2" build_dir="${SCRATCH}/probe-$1"
  shift 2

  cmake -S "$PROBE_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    ${EXTRA_CMAKE_ARGS[@]+"${EXTRA_CMAKE_ARGS[@]}"} \
    "$@"
  cmake --build "$build_dir" --config Release

  local exe="${build_dir}/perf-context-probe"
  [[ -x "$exe" ]] || exe="${build_dir}/Release/perf-context-probe.exe"
  [[ -x "$exe" ]] || { echo "::error::Probe binary not found under $build_dir" >&2; exit 1; }

  "$exe" "$expectation" "${SCRATCH}/db-${name}"
}

run_probe enabled enabled
run_probe disabled disabled -DROCKSDB_LIBRARY_OVERRIDE="$DISABLED_LIB"
echo "Both archived libraries behave as their path claims"
