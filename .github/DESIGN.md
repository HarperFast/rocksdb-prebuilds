# Build pipeline

## The two PerfContext variants in one archive

**Invariant.** Every release archive holds two *release* RocksDB static libraries, built from the
same source, patches, architecture and configure options, differing only in `WITH_PERF_CONTEXT`; the
library at the historical `lib/` path is always the PerfContext-**enabled** one. The debug library
under `debug/lib/` is unchanged and exists only in the enabled variant: it is large, and no consumer
links it.

**Why it has to be stated.** Nothing in the artifact distinguishes the two files. They have the same
basename, the same ABI, the same headers and nearly the same size, so a build that silently produced
one library twice, or that swapped them, would publish an archive that passes every structural check
and only fails for a consumer, after the release is immutable. The enabled library is also the one
whose path consumers already link, so "which file is which" is a compatibility guarantee, not a
detail.

**Where the code enforces it.**

- `vcpkg-overlays/rocksdb/vcpkg.json` makes the variant a vcpkg feature (`no-perf-context`) rather
  than an environment variable. A feature is part of the port's ABI hash, so the second install
  cannot be served the first one's binary-cache entry; an environment variable would be invisible to
  that hash. Both installs then run the same portfile, which is what makes "identical apart from
  `WITH_PERF_CONTEXT`" structural instead of a second flag list that can drift.
- `vcpkg-overlays/rocksdb/portfile.cmake` asserts the five compression features resolved ON, so the
  second install cannot quietly lose them, and reads `NPERF_CONTEXT` back out of the generated build
  system after configuring. vcpkg only *warns* when a `-D` names a variable the project never
  declared, so checking the resolved definition rather than the option is what catches an upstream
  rename — on all ten targets, including the cross-compiled ones no symbol scan or probe can reach.
- `.github/scripts/build-rocksdb-variants.sh` is called by both the native and the musl job, so the
  two build paths cannot diverge. It fails the job before an archive exists if the headers differ
  between variants, if the staged enabled library changed during the second install, or if the two
  staged libraries hash the same.
- `.github/scripts/verify-prebuild-archive.sh` re-checks all of that from a fresh extraction of the
  finished archive. Its counter-name check is the one that reaches every target: perf-counter names
  only reach `.rodata` through `PerfContext::ToString()`, which `NPERF_CONTEXT` compiles away, so
  counting `user_key_comparison_count` in the archived library separates the variants with no
  toolchain and no matching architecture. It is a comparison, not a presence test, because the same
  name is a `PerfContextBase` field and vcpkg compiles release objects with `/Z7`, so on Windows it
  also reaches the archive as CodeView type info — identically for both variants, which is what
  leaves the literal as the enabled library's margin. A control string present in both guards the
  search itself, because a search that silently matched nothing would pass as an absence. The `nm` check adds
  a second, independent reading on the eight non-Windows targets. Both are asserted in **both**
  directions: a one-sided check still passes when the two libraries are swapped.
- `tools/perf-context-probe` links each archived library in turn and asserts
  `user_key_comparison_count` is non-zero for the enabled one and zero for the disabled one. The
  matrix's `run_probe` is false exactly where the runner cannot execute the target's binaries
  (`darwin-x64`, both `windows-arm64` targets).
