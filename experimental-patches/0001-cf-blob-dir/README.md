# 0001-cf-blob-dir

**Target RocksDB version:** see [`patched-version.txt`](patched-version.txt) (`v11.8.1`), which is
the single source of truth — the PR gate reads it to decide which release to build against.

Adds `AdvancedColumnFamilyOptions::blob_dir` so blob files can live on a different volume than the
SST files, and defines `ROCKSDB_HAS_CF_BLOB_DIR` for feature detection. Consumed by
`@harperfast/rocksdb-js` via its `blobs.dir` open option.

Stock RocksDB derives every blob file path from `cf_paths.front().path`, so `db_paths`/`cf_paths`
cannot tier large values — they distribute SST files by level while every blob file stays put. This
patch routes all blob path derivation through a single `ImmutableCFOptions::GetBlobDir()`, so the
option and its `cf_paths.front()` default cannot drift apart.

## Risks

- **Not ABI-compatible with stock RocksDB.** The added C++ field changes the layout of RocksDB
  option types, so consumers must rebuild against the patched headers. `blob_dir` is deliberately
  the *last* field of `AdvancedColumnFamilyOptions` — inserting mid-struct shifts every following
  field's offset and silently mismatches code compiled against stock headers.
- **Checkpoint and BackupEngine refuse a DB with `blob_dir` set.** A backup taken before the first
  blob file exists restores into a database pointed at the *source's* blob directory, whose
  obsolete-file scan then deletes the source's live blob files. The guard keys on the option being
  set at all, rather than on the files reported.
- **The immutability rule is enforced by the consumer.** A blob file's directory is re-derived from
  the option on every open rather than recorded per file, so changing it on a populated database
  strands the blob files. `rocksdb-js` compares against the `blob_dir` persisted in the OPTIONS file.

## Re-auditing after a version bump

`verify-blob-path-inventory.sh` snapshots every `BlobFileName(` call site and every
`cf_paths[0].path` site in the *patched* tree, then diffs them against
[`blob-path-inventory.txt`](blob-path-inventory.txt) and
[`cf-blob-path-inventory.txt`](cf-blob-path-inventory.txt). It intentionally pins paths, line
numbers, and source text, so any upstream call-site change requires review — that is how a new
blob-path derivation site upstream is caught instead of silently writing blob files to the wrong
directory.

```sh
# audit a patched tree (exits non-zero on drift)
./verify-blob-path-inventory.sh ROCKSDB_SOURCE_DIR

# after reviewing legitimate upstream changes, regenerate both inventories
./verify-blob-path-inventory.sh --update ROCKSDB_SOURCE_DIR
```

Bump `patched-version.txt` in the same commit that rebases the patch and regenerates the
inventories. Requires `ripgrep`.
