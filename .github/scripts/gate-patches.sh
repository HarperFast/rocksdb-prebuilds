#!/usr/bin/env bash
# See .github/DESIGN.md.
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

# The file is PR-controlled and becomes part of a URL, so it must be tag-shaped.
read_pin() {
  if [[ ! -s "$1" ]]; then
    echo "::error::$1 is missing or empty"
    exit 1
  fi
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

# Present but non-executable is an error, never a silent skip.
run_hook() {
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
official_failed=0
read_pin vcpkg-overlays/rocksdb/patched-version.txt
official_pin="$pin"

echo "::group::official patches against $official_pin"
fresh_tree "$official_pin"
if ! .github/scripts/apply-patches.sh "$src"; then
  echo "::error::the official patches do not apply to RocksDB $official_pin; rebase them, or set vcpkg-overlays/rocksdb/patched-version.txt to the tag they target"
  failed=1
  official_failed=1
fi
echo "::endgroup::"

for dir in experimental-patches/*/; do
  name="$(basename "$dir")"
  if [[ ! -f "${dir}patched-version.txt" ]]; then
    echo "::notice::$name has no patched-version.txt; skipping its gate"
    continue
  fi
  read_pin "${dir}patched-version.txt"

  # A stale patch cannot ship (the release audit refuses it), so it gates only a PR that changes it.
  if [[ "$pin" != "$official_pin" ]] && ! dir_changed "$name"; then
    echo "::warning::$name is pinned to $pin while the official patches target $official_pin. This PR does not change it, so it is not gated; rebase it onto $official_pin and update its patched-version.txt before building it"
    continue
  fi

  if [[ "$pin" == "$official_pin" && "$official_failed" -eq 1 ]]; then
    echo "::notice::$name not checked: the official patches do not apply at $pin"
    continue
  fi

  echo "::group::$name against $pin"
  fresh_tree "$pin"
  if .github/scripts/apply-patches.sh "$src" "$name"; then
    run_hook "$name" "${dir}audit.sh" || failed=1
    run_hook "$name" "${dir}test.sh" || failed=1
  else
    echo "::error::the official patches and then $name do not apply at $pin; rebase $name onto $official_pin and update its patched-version.txt"
    failed=1
  fi
  echo "::endgroup::"
done

exit "$failed"
