`patches/0001-fix-dependencies.patch` is from the vcpkg repository and licensed under the MIT
license (notice below).

https://github.com/toge/vcpkg/tree/master/ports/rocksdb

Patches numbered 0002 and above are downstream (HarperFast) changes to RocksDB itself, applied to
the upstream release tarball by `.github/workflows/build.yml` before the vcpkg build. Each carries
a header describing what it changes and why. They must be rebased when the pinned RocksDB version
moves. Apply them with `patch -p1 -F0`, then run
`verify-blob-path-inventory.sh ROCKSDB_SOURCE_DIR`. The audit intentionally pins paths, line
numbers, and source text so every upstream call-site change requires review. After reviewing a
legitimate change, regenerate both inventories with
`verify-blob-path-inventory.sh --update ROCKSDB_SOURCE_DIR`.

- `0002-cf-blob-dir.patch` — adds `AdvancedColumnFamilyOptions::blob_dir` so blob files can live on
  a different volume than the SST files, and defines `ROCKSDB_HAS_CF_BLOB_DIR` for feature
  detection. Consumed by `@harperfast/rocksdb-js` via its `blobs.dir` open option.

MIT License

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
