# Experimental patches

Downstream, experimental RocksDB patches that are **not** applied by default.

The official vcpkg patches in [`vcpkg-overlays/rocksdb/patches/`](../vcpkg-overlays/rocksdb/patches/)
are applied to every build. The patches here are opt-in: a build applies one only
when its id is passed to the `experimental_patches` input of the
[build workflow](../.github/workflows/build.yml). Scheduled (nightly) builds never
apply them.

## Layout

Each patch lives in its own directory named `<id>-<slug>`:

```
experimental-patches/
  0000-example-noop/
    0000-example-noop.patch   # one or more *.patch files, applied with `patch -p1 -F0`
    README.md                 # what it does, target RocksDB version, risks
  0001-cf-blob-dir/
    0001-cf-blob-dir.patch
    README.md
    patched-version.txt       # optional: the upstream tag this was verified against
    audit.sh                  # optional: cheap check, runs on PRs and nightly
    test.sh                   # optional: expensive check, runs on PRs only
    ...                       # any other support files the patch needs
```

Only `*.patch` files are applied; anything else in the directory is inert to the
build, so a patch can keep whatever support files it needs beside it.

- **id** — everything before the first `-`. Ids must be unique. Numeric ids are
  compared by value, so `1`, `01`, and `0001` are the *same* id and cannot coexist
  (enforced by the [validation workflow](../.github/workflows/validate-experimental-patches.yml)).
  Zero-pad if you like the directory to sort naturally past 9; padding is cosmetic.
- **slug** — a short human-readable name.
- Non-numeric ids (e.g. `blobdir`) are allowed and compared as exact strings. Since
  the id is everything before the first `-`, an id itself cannot contain a dash
  (`blob-dir` has id `blob`, slug `dir`).

Every file and directory name here must also be **checkout-able on Windows**, since
each release builds on Windows runners and one unusable path fails `actions/checkout`
and takes down the whole release — not just experimental builds. Names are limited to
`[A-Za-z0-9._-]`, may not end in a dot or space, may not be a reserved DOS device name
(`CON`, `PRN`, `AUX`, `NUL`, `COM0`-`9`, `LPT0`-`9`), and may not differ from another
path only by case. The validation workflow enforces all of this and a Windows checkout
job backstops it.

## Running an experimental build

Dispatch the build workflow with a comma-separated list of ids, e.g. `1, 3, 4`.
Ids are resolved to directories, sorted by id, and applied in that order after the
official patches. Within a single directory, multiple `.patch` files apply in
`LC_ALL=C` lexicographic order — zero-pad their names (`01-`, `02-`) if one must
apply before another, since `10-x.patch` otherwise sorts before `2-y.patch`. The resulting build is published as a prerelease tagged
`v<version>-experimental-<ids>` (e.g. `v11.8.1-experimental-1-3-4`), so it never
collides with a clean release and is obviously experimental.

## Patch authoring

Patches apply with `patch -p1 -F0` (zero fuzz) against a fresh upstream tarball.
Author against a specific RocksDB version and record it in the patch's README — this way, a version bump that shifts a hunk's context fails the build loudly instead of silently landing in the wrong place.

## Verification hooks

Three optional files let a patch carry its own verification, so
[`build.yml`](../.github/workflows/build.yml) needs no knowledge of any particular patch:

| File | Purpose |
|---|---|
| `patched-version.txt` | The upstream tag (e.g. `v11.8.1`) the patch was verified against. Without it the PR gate cannot know what to build, and skips that patch. |
| `audit.sh <src>` | Cheap check against the **already-patched** source tree. Runs on every PR *and* nightly against the release being built. |
| `test.sh <src>` | Expensive check (building and running upstream tests). Runs on PRs only. |

Both hooks receive the patched RocksDB source directory and should exit non-zero on
failure, and a hook that exists but is not executable is an error rather than a
silent skip.

On a PR they gate the merge. The nightly runs `audit.sh` only, against the release
being built, and **fails only the builds that actually apply the patch**: a plain
nightly reports drift as a warning and still ships, while a dispatched
`experimental_patches` build that includes a drifted patch is blocked. Both halves
matter — an experimental patch must not break a release it is not in, but it must
also never ship in one that *does* include it without passing its own audit.
