# RocksDB Prebuilds

Automated RocksDB prebuilt binaries for Linux, macOS, and Windows.

The static RocksDB builds include bzip2, lz4, snappy, zlib, and zstd compression support.

## PerfContext variants

Each archive contains **two** RocksDB static libraries, built from the same source, the same
patches, the same architecture and the same configure options, differing only in
`WITH_PERF_CONTEXT`. The number of release archives is unchanged, at one per platform target.

| Path in the archive | PerfContext | Who it is for |
|---|---|---|
| `lib/librocksdb.a`, `lib/rocksdb.lib` | enabled | the default; what every release has always shipped |
| `lib/no-perf-context/librocksdb.a`, `lib/no-perf-context/rocksdb.lib` | compiled out | consumers that never read the counters and want the comparison hot path back |

Everything else is shared: one copy of the public headers under `include/`, one set of compression
dependency libraries in `lib/`, and one CMake package and pkg-config file. The headers are identical
for both variants — the build fails if they ever stop being — so either library can be compiled
against them.

### Linking the PerfContext-disabled library

Select it by path. Keep the same include directory and the same dependency libraries, and replace
only the RocksDB library:

```
-I<prefix>/include  <prefix>/lib/no-perf-context/librocksdb.a  -L<prefix>/lib -lzstd -llz4 -lsnappy -lz -lbz2
```

```
/I<prefix>\include  <prefix>\lib\no-perf-context\rocksdb.lib  <prefix>\lib\zstd.lib …
```

With CMake, `find_package(RocksDB CONFIG)` resolves the **enabled** library, because the archive
ships one CMake package and it describes `lib/`. The package resolves its own zlib, including the
`zs.lib` that vcpkg installs on Windows, so no `ZLIB_USE_STATIC_LIBS` or other preparation is needed
on any target. To take the other library, override the imported target's location after importing
it:

```cmake
find_package(RocksDB CONFIG REQUIRED)
set_target_properties(RocksDB::rocksdb PROPERTIES
  IMPORTED_LOCATION "${prefix}/lib/no-perf-context/librocksdb.a"
  IMPORTED_LOCATION_RELEASE "${prefix}/lib/no-perf-context/librocksdb.a")
```

Only the release library has a second variant. `debug/lib/librocksdbd.a` (`rocksdbd.lib`) is the
PerfContext-enabled build and has no `no-perf-context` counterpart, so a Debug-configuration build
keeps resolving `IMPORTED_LOCATION_DEBUG` to the enabled library whatever the override above sets.

`pkg-config rocksdb` likewise names the enabled library. Link exactly one of the two: putting both
on a link line is an error, not a preference.

rocksdb-js is the consumer this path exists for. It links the prebuild directly rather than through
the CMake package, so selecting the variant is a change to the RocksDB library path it passes to the
linker — `lib/no-perf-context/librocksdb.a` instead of `lib/librocksdb.a`, with its include and
dependency-library flags untouched. Releases published before this change have no
`lib/no-perf-context/` directory, so a consumer that asks for it must fail with a clear error rather
than quietly fall back to `lib/librocksdb.a` and link the instrumented library it was trying to
avoid.

### What the disabled variant gives up

`WITH_PERF_CONTEXT=OFF` defines `NPERF_CONTEXT`, which compiles every `PERF_COUNTER_*` and
`PERF_TIMER_*` macro in RocksDB to nothing. Against that library:

- `rocksdb::get_perf_context()` still links and returns a valid pointer, but every counter stays
  zero, whatever `SetPerfLevel()` is set to. There is no error and no warning; code that reads the
  counters silently sees zeros.
- `PerfContext::ToString()` returns an empty string.
- The `rocksdb.db.mutex.wait.micros` statistic is never recorded. RocksDB records it through the
  same perf-timer macro and only at `StatsLevel::kAll`; at the default stats level it was never
  recorded anyway.
- `IOStatsContext` is **not** affected. `WITH_IOSTATS_CONTEXT` stays on in both variants, so
  `get_iostats_context()` keeps working and `BackupEngine`, which relies on it, is unaffected.

Nothing else differs. The two libraries have the same ABI and the same compression support, and a
database written by one is readable by the other.

Releases: https://github.com/HarperFast/rocksdb-prebuilds/releases

To publish a prerelease build of a RocksDB version (for example, to validate a build configuration
change before the final release), manually run the workflow with that `rocksdb_version` and a
`prerelease_revision`. The revision is one semver prerelease identifier - lowercase letters,
digits, and hyphens only, with no dots and no leading zero on a purely numeric value - so `1`
publishes `v11.1.2-1` and `rc2` publishes `v11.1.2-rc2`. Either sorts before the final `v11.1.2`
release and does not replace it. The `experimental` prefix is reserved for `experimental_patches`
builds.

| OS       | Arch                  | CRT Linkage     | Library Linkage | Filename |
|----------|-----------------------|-----------------|-----------------|----------|
| Linux    | arm64 (glibc)         | dynamic         | static          | rocksdb-X.Y.Z-linux-arm64-glibc.tar.xz |
| Linux    | arm64 (musl)          | dynamic         | static          | rocksdb-X.Y.Z-linux-arm64-musl.tar.xz |
| Linux    | x64 (glibc)           | dynamic         | static          | rocksdb-X.Y.Z-linux-x64-glibc.tar.xz |
| Linux    | x64 (musl)            | dynamic         | static          | rocksdb-X.Y.Z-linux-x64-musl.tar.xz |
| macOS    | arm64 (Apple Silicon) | dynamic         | static          | rocksdb-X.Y.Z-darwin-arm64.tar.xz |
| macOS    | x64 (Intel)           | dynamic         | static          | rocksdb-X.Y.Z-darwin-x64.tar.xz |
| Windows  | arm64                 | static (`/MT`)  | static          | rocksdb-X.Y.Z-windows-arm64.tar.xz |
| Windows  | arm64                 | dynamic (`/MD`) | static          | rocksdb-X.Y.Z-windows-arm64-static-md.tar.xz |
| Windows  | x64                   | static (`/MT`)  | static          | rocksdb-X.Y.Z-windows-x64.tar.xz  |
| Windows  | x64                   | dynamic (`/MD`) | static          | rocksdb-X.Y.Z-windows-x64-static-md.tar.xz |

## Windows Builds

We provide both the static and dynamically linked runtime versions of RocksDB for Windows.

The dynamic (`/MD`) build requires users to install the VC++ redistributable and best suited for
internal tools and corporate environments.

The static (`/MT`) build is self-contained and does not require the VC++ redistributable. It is best
suited for projects that need to be portable, self-contained such as consumer applications.
