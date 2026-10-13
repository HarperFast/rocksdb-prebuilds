#!/usr/bin/env bash
# PR gate for the patch sets. Each is applied at the upstream tag its patched-version.txt
# declares: the official patches at vcpkg-overlays/rocksdb's, and each experimental patch, on
# top of the official ones, at its own. See .github/DESIGN.md.
#
# usage: gate-patches.sh CHANGED_FILES
#   CHANGED_FILES lists the paths this PR changes, one per line.
set -euo pipefail
shopt -s nullglob

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 CHANGED_FILES" >&2
  exit 2
fi
changed_files="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
src="$work/src"

# Sets $pin. The file is PR-controlled and becomes part of a URL, so it must be tag-shaped.
read_pin() {
  pin="$(tr -d '[:space:]' < "$1")"
  if [[ ! "$pin" =~ ^v[0-9][0-9A-Za-z.-]*$ ]]; then
    echo "::error::$1 must hold one RocksDB tag such as v11.8.1 (got '$pin')"
    exit 1
  fi
}

# Infrastructure failures exit outright: they say nothing about the patches.
fresh_tree() {
  local tag="$1" tarball="$work/$1.tar.gz"
  if [[ ! -f "$tarball" ]] && ! curl -sfL --retry 3 -o "$tarball" \
    "https://github.com/facebook/rocksdb/archive/refs/tags/$tag.tar.gz"; then
    echo "::error::could not download RocksDB $tag"
    exit 1
  fi
  rm -rf "$src"
  mkdir "$src"
  if ! tar -xzf "$tarball" -C "$src" --strip-components=1; then
    echo "::error::could not extract RocksDB $tag"
    exit 1
  fi
}

run_hook() {   # name, hook file -- present but non-executable is an error, never a silent skip
  local name="$1" hook="$2"
  [[ -f "$hook" ]] || return 0
  if [[ ! -x "$hook" ]]; then
    echo "::error::$name: $(basename "$hook") is not executable; chmod +x it"
    return 1
  fi
  echo "Running $(basename "$hook") for $name"
  "$hook" "$src"
}

dir_changed() {
  local path
  while IFS= read -r path; do
    [[ "$path" == "experimental-patches/$1/"* ]] && return 0
  done < "$changed_files"
  return 1
}

failed=0
read_pin vcpkg-overlays/rocksdb/patched-version.txt
official_pin="$pin"

echo "::group::official patches against $official_pin"
fresh_tree "$official_pin"
if ! .github/scripts/apply-patches.sh "$src"; then
  echo "::error::the official patches do not apply to RocksDB $official_pin; rebase them, or set vcpkg-overlays/rocksdb/patched-version.txt to the tag they target"
  failed=1
fi
echo "::endgroup::"

for dir in experimental-patches/*/; do
  name="$(basename "$dir")"
  if [[ ! -f "${dir}patched-version.txt" ]]; then
    echo "::notice::$name has no patched-version.txt; skipping its gate"
    continue
  fi
  read_pin "${dir}patched-version.txt"

  echo "::group::$name against $pin"
  fresh_tree "$pin"
  if .github/scripts/apply-patches.sh "$src" "$name"; then
    run_hook "$name" "${dir}audit.sh" || failed=1
    run_hook "$name" "${dir}test.sh" || failed=1
    echo "::endgroup::"
    continue
  fi

  # Tell "this patch conflicts with the official ones" from "the official ones have moved
  # past this patch's pin": only the first is necessarily something this PR broke.
  fresh_tree "$pin"
  if .github/scripts/apply-patches.sh "$src"; then
    echo "::error::$name does not apply on top of the official patches at $pin; rebase it"
    failed=1
  elif [[ "$pin" == "$official_pin" ]] || dir_changed "$name"; then
    echo "::error::$name is pinned to $pin, where the official patches do not apply; rebase it onto $official_pin and update its patched-version.txt"
    failed=1
  else
    echo "::warning::$name is pinned to $pin, where the official patches (which target $official_pin) no longer apply. This PR does not change it, so it does not block; rebase it onto $official_pin before building it"
  fi
  echo "::endgroup::"
done

exit "$failed"
