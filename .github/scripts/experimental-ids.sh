#!/usr/bin/env bash
# Shared id canonicalization for the experimental-patches pipeline.
#
# The validator and the build resolver MUST agree on this: if they disagree, a
# dispatched id resolves to a different directory than the one validation approved.
# That is why it lives in one file instead of being duplicated into both workflows.

# Canonical key for an experimental patch id:
#   numeric -> n:<decimal string, leading zeros stripped>  (1 == 01 == 0001)
#   other   -> s:<exact string>
#
# Deliberately string-based. Bash arithmetic is signed 64-bit, so $((10#$id)) wraps:
# 18446744073709551617 silently becomes 1, which would alias a large id onto an
# unrelated one and publish the build under the wrong tag.
canon_id() {
  local v="$1"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    local stripped="${v#"${v%%[!0]*}"}"
    printf 'n:%s' "${stripped:-0}"
  else
    printf 's:%s' "$v"
  fi
}

# Collision key for id uniqueness: the canonical id, case-folded. Two ids differing
# only by case would produce release tags that cannot coexist in a files-backend git
# clone on a case-insensitive filesystem.
canon_collision_key() {
  local k
  k="$(canon_id "$1")"
  printf '%s' "${k,,}"
}

# Validate one experimental-patches directory against every invariant the pipeline
# depends on. Prints one message per failure and returns 1; silent and returns 0 if OK.
#
# Both the validator and the build resolver call this. The resolver also runs on
# branches that never passed validation, and enforcing only a subset there is how a
# build publishes `-experimental-<id>` for a directory holding no .patch at all, or
# resolves an id whose charset would collide with the `<ids>.<revision>` tag form.
validate_patch_dir() {
  local dir="$1" name id slug rc=0
  name="$(basename "$dir")"

  if [[ "$name" != *-* ]]; then
    echo "'$name' must be named <id>-<slug> (no '-' found)"
    return 1
  fi

  id="${name%%-*}"
  slug="${name#*-}"

  # The id becomes a semver prerelease segment, so a dot (`1.2`) or `+` would
  # re-segment the tag and collide with `<ids>.<revision>`; any shell metacharacter
  # would also be unsafe where the resolved name is used unquoted. The slug never
  # reaches the tag but must stay shell- and Windows-safe.
  if [[ ! "$id" =~ ^[A-Za-z0-9]+$ ]]; then
    echo "'$name' has a non-alphanumeric id ('$id'); ids must match ^[A-Za-z0-9]+\$"
    rc=1
  fi
  if [[ ! "$slug" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "'$name' has an invalid slug ('$slug'); slugs must match ^[A-Za-z0-9._-]+\$"
    rc=1
  fi
  if ! compgen -G "${dir%/}/*.patch" > /dev/null; then
    echo "'$name' contains no .patch file"
    rc=1
  fi

  return "$rc"
}
