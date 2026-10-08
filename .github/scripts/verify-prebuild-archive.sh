#!/usr/bin/env bash
# Verify a finished release archive, from a fresh extraction of the archive itself.
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

# Only PerfContext::ToString() puts a counter name in .rodata, and NPERF_CONTEXT compiles it away.
# The control is an unrelated statistics name, present whatever the variant.
readonly PERF_MARKER="user_key_comparison_count"
readonly CONTROL_MARKER="rocksdb.db.get.micros"

read -ra EXTRA_CMAKE_ARGS <<< "${PROBE_CMAKE_ARGS:-}" || true

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# grep exits 1 for "no match" and 2 or more for a real failure; a failure read as "no match" would
# turn every absence check below into an unconditional pass.
MATCH_COUNT=0
count_matches() {
  local rc=0
  MATCH_COUNT="$(LC_ALL=C grep -a -c -F -- "$1" "$2")" || rc=$?
  if (( rc > 1 )); then
    echo "::error::Could not search ${2##*/} for '$1' (grep exit $rc)" >&2
    exit 1
  fi
}

SYMBOL_REFS=0
count_perf_context_symbol_refs() {
  local symbols rc=0
  if ! symbols="$(nm -A "$1")"; then
    echo "::error::nm failed on ${1##*/}; the PerfContext symbol check cannot run" >&2
    exit 1
  fi
  SYMBOL_REFS="$(grep -cE ' U _{1,2}Z(TW|TH)?N7rocksdb12perf_contextE$' <<< "$symbols")" || rc=$?
  if (( rc > 1 )); then
    echo "::error::Could not scan ${1##*/} for rocksdb::perf_context references (grep exit $rc)" >&2
    exit 1
  fi
}

mkdir -p "$PREFIX"
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
VARIANT_ENTRIES="$(find "${PREFIX}/lib/${VARIANT_SUBDIR}" -mindepth 1 | wc -l | tr -d '[:space:]')"
readonly VARIANT_ENTRIES
if [[ "$VARIANT_ENTRIES" != "1" ]]; then
  echo "::error::lib/${VARIANT_SUBDIR} holds $VARIANT_ENTRIES entries; expected only ${LIB_NAME}" >&2
  find "${PREFIX}/lib/${VARIANT_SUBDIR}" -mindepth 1 >&2
  exit 1
fi
echo "lib/${LIB_NAME} and lib/${VARIANT_SUBDIR}/${LIB_NAME} are both present and distinct"

# The only variant check needing no toolchain and no matching architecture, so it is the one the
# cross-compiled targets rest on. Asserted in both directions: a one-sided check still passes when
# the two libraries have been swapped.
echo "=== PerfContext counter names ==="
for lib in "$ENABLED_LIB" "$DISABLED_LIB"; do
  count_matches "$CONTROL_MARKER" "$lib"
  if [[ "$MATCH_COUNT" -eq 0 ]]; then
    echo "::error::${lib#"${PREFIX}/"} does not contain the control string '$CONTROL_MARKER'; the counter-name check cannot tell the variants apart here" >&2
    exit 1
  fi
done
count_matches "$PERF_MARKER" "$ENABLED_LIB"
readonly ENABLED_MARKERS="$MATCH_COUNT"
count_matches "$PERF_MARKER" "$DISABLED_LIB"
readonly DISABLED_MARKERS="$MATCH_COUNT"
echo "lib/${LIB_NAME}: $ENABLED_MARKERS match(es); lib/${VARIANT_SUBDIR}/${LIB_NAME}: $DISABLED_MARKERS"
if [[ "$ENABLED_MARKERS" -eq 0 ]]; then
  echo "::error::lib/${LIB_NAME} does not contain '$PERF_MARKER'; the default path is not the PerfContext-enabled library" >&2
  exit 1
fi
if [[ "$DISABLED_MARKERS" -ne 0 ]]; then
  echo "::error::lib/${VARIANT_SUBDIR}/${LIB_NAME} contains '$PERF_MARKER'; WITH_PERF_CONTEXT=OFF did not reach the compiler" >&2
  exit 1
fi

if [[ "$LIB_NAME" == "librocksdb.a" ]]; then
  echo "=== PerfContext symbol references ==="
  count_perf_context_symbol_refs "$ENABLED_LIB"
  readonly ENABLED_REFS="$SYMBOL_REFS"
  count_perf_context_symbol_refs "$DISABLED_LIB"
  readonly DISABLED_REFS="$SYMBOL_REFS"
  echo "lib/${LIB_NAME}: $ENABLED_REFS references; lib/${VARIANT_SUBDIR}/${LIB_NAME}: $DISABLED_REFS references"
  if [[ "$ENABLED_REFS" -eq 0 ]]; then
    echo "::error::lib/${LIB_NAME} has no rocksdb::perf_context references; the default path is not the PerfContext-enabled library" >&2
    exit 1
  fi
  if [[ "$DISABLED_REFS" -ne 0 ]]; then
    echo "::error::lib/${VARIANT_SUBDIR}/${LIB_NAME} has $DISABLED_REFS rocksdb::perf_context references; WITH_PERF_CONTEXT=OFF did not apply" >&2
    exit 1
  fi
fi

if [[ "$RUN_PROBE" != "true" ]]; then
  echo "::notice::Behavioural probe skipped: this target is cross-compiled and its binaries cannot run on this runner"
  exit 0
fi

echo "=== Behavioural probe ==="
# GITHUB_WORKSPACE is a backslash path on Windows runners, and CMake reads backslashes in a -D value
# as string escapes.
cmake_path() { printf '%s' "${1//\\//}"; }

run_probe() {
  local name="$1" expectation="$2" build_dir="${SCRATCH}/probe-$1"
  shift 2

  cmake -S "$(cmake_path "$PROBE_DIR")" -B "$(cmake_path "$build_dir")" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$(cmake_path "$PREFIX")" \
    ${EXTRA_CMAKE_ARGS[@]+"${EXTRA_CMAKE_ARGS[@]}"} \
    "$@"
  cmake --build "$(cmake_path "$build_dir")" --config Release

  local exe="${build_dir}/perf-context-probe"
  [[ -x "$exe" ]] || exe="${build_dir}/Release/perf-context-probe.exe"
  [[ -x "$exe" ]] || { echo "::error::Probe binary not found under $build_dir" >&2; exit 1; }

  "$exe" "$expectation" "${SCRATCH}/db-${name}"
}

run_probe enabled enabled
run_probe disabled disabled -DROCKSDB_LIBRARY_OVERRIDE="$(cmake_path "$DISABLED_LIB")"
echo "Both archived libraries behave as their path claims"
