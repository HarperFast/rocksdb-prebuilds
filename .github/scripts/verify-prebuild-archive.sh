#!/usr/bin/env bash
# Verify a finished release archive, from a fresh extraction of the archive itself.
#
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: ARCHIVE=<path.tar.xz> .github/scripts/verify-prebuild-archive.sh

Verifies a finished release archive from a fresh extraction of the archive itself.

Required:
  ARCHIVE           the .tar.xz to verify

Optional:
  SCRATCH           working directory for the extraction and probe build (default: a new temp dir)
  PROBE_DIR         tools/perf-context-probe (default: derived from this script's location)
  RUN_PROBE         true (default) to compile and run the probe; false for a cross-compiled target
  PROBE_CMAKE_ARGS  whitespace-separated extra CMake arguments (MSVC runtime selection).
                    Spell any path value with forward slashes; these are passed through as given.
USAGE
}

if [[ -z "${ARCHIVE:-}" ]]; then
  echo "verify-prebuild-archive.sh: missing required environment: ARCHIVE" >&2
  echo >&2
  usage
  exit 2
fi

# GITHUB_WORKSPACE is a backslash path on Windows runners; tar rejects one as its -C directory and
# CMake reads the backslashes in a -D value as escapes. On every other shell a backslash is an
# ordinary filename character, so rewrite only here, and ahead of each path's first reader.
windows_paths=false
case "${OSTYPE:-$(uname -s)}" in
  msys* | cygwin* | win32 | MINGW* | MSYS* | CYGWIN*) windows_paths=true ;;
esac

if [[ "$windows_paths" == true ]]; then
  ARCHIVE="${ARCHIVE//\\//}"
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "verify-prebuild-archive.sh: no such archive: $ARCHIVE" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROBE_DIR:=$(cd "${script_dir}/../.." && pwd)/tools/perf-context-probe}"
: "${RUN_PROBE:=true}"
if [[ -z "${SCRATCH:-}" ]]; then
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/rocksdb-archive-check.XXXXXX")"
  echo "Extracting and probing under $SCRATCH"
fi
if [[ "$windows_paths" == true ]]; then
  PROBE_DIR="${PROBE_DIR//\\//}"
  SCRATCH="${SCRATCH//\\//}"
fi

readonly VARIANT_SUBDIR="no-perf-context"
readonly PREFIX="${SCRATCH}/extracted"

# Only PerfContext::ToString() puts a counter name in .rodata, and NPERF_CONTEXT compiles it away —
# but the same name is also a PerfContextBase field, and vcpkg compiles release objects with /Z7, so
# on Windows it also reaches the archive as CodeView type info. Both variants declare that struct
# identically, so the literal is what makes the enabled library's count strictly the larger one;
# presence alone would fail every Windows target. The control is an unrelated statistics name,
# present whatever the variant, so a search that silently matched nothing cannot pass as an absence.
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
# turn every count below into a passing zero.
MATCH_COUNT=0
count_matches() {
  local rc=0 matches
  matches="$(LC_ALL=C grep -o -a -F -- "$1" "$2")" || rc=$?
  if (( rc > 1 )); then
    echo "::error::Could not search ${2##*/} for '$1' (grep exit $rc)" >&2
    exit 1
  fi
  if (( rc == 1 )); then
    MATCH_COUNT=0
  else
    MATCH_COUNT="$(printf '%s\n' "$matches" | wc -l | tr -d '[:space:]')"
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

# Asserted in both directions: a one-sided check still passes when the two libraries are swapped.
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
echo "'$PERF_MARKER' in lib/${LIB_NAME}: $ENABLED_MARKERS; in lib/${VARIANT_SUBDIR}/${LIB_NAME}: $DISABLED_MARKERS"
if [[ "$ENABLED_MARKERS" -eq 0 ]]; then
  echo "::error::lib/${LIB_NAME} does not contain '$PERF_MARKER'; the default path is not the PerfContext-enabled library" >&2
  exit 1
fi
if [[ "$ENABLED_MARKERS" -le "$DISABLED_MARKERS" ]]; then
  echo "::error::lib/${VARIANT_SUBDIR}/${LIB_NAME} contains '$PERF_MARKER' at least as often ($DISABLED_MARKERS) as lib/${LIB_NAME} ($ENABLED_MARKERS); WITH_PERF_CONTEXT=OFF did not reach the compiler, or the two libraries are the wrong way round" >&2
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
run_probe() {
  local name="$1" expectation="$2" build_dir="${SCRATCH}/probe-$1"
  shift 2

  cmake -S "$PROBE_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    ${EXTRA_CMAKE_ARGS[@]+"${EXTRA_CMAKE_ARGS[@]}"} \
    "$@"
  cmake --build "$build_dir" --config Release

  # Single-config generators put it at the top of the build dir, multi-config ones under Release/.
  local exe="" candidate
  for candidate in \
    "${build_dir}/perf-context-probe" \
    "${build_dir}/perf-context-probe.exe" \
    "${build_dir}/Release/perf-context-probe.exe"; do
    if [[ -x "$candidate" ]]; then
      exe="$candidate"
      break
    fi
  done
  if [[ -z "$exe" ]]; then
    echo "::error::Probe binary not found under $build_dir" >&2
    exit 1
  fi

  "$exe" "$expectation" "${SCRATCH}/db-${name}"
}

run_probe enabled enabled
run_probe disabled disabled -DROCKSDB_LIBRARY_OVERRIDE="$DISABLED_LIB"
echo "Both archived libraries behave as their path claims"
