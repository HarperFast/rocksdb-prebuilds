# 0000-example-noop

**Target RocksDB version:** v11.8.1

Example/template experimental patch. Inserts a no-op marker comment into
`include/rocksdb/version.h`; it changes no behavior and exists only to exercise the
experimental-patches pipeline end to end.

To try it, dispatch the build workflow with `rocksdb_version: 11.8.1` and
`experimental_patches: 0`. The resulting prerelease is tagged
`v11.8.1-experimental-0`.

Because it is pinned to v11.8.1 and applied with `patch -p1 -F0`, running it against
a different version fails loudly — that is the intended demonstration of the
zero-fuzz guard, not a bug.
