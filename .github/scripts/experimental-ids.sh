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
