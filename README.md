# RocksDB Prebuilds

Automated RocksDB prebuilt binaries for Linux, macOS, and Windows.

Releases: https://github.com/HarperFast/rocksdb-prebuilds/releases

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
