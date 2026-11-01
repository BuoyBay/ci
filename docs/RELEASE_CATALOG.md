# SDK release catalog and build matrix

`src/releases.bui` is the native, offline catalog tool. It reads captured GitHub
release metadata, retains every release and asset, verifies the supplied metadata,
and produces image plans. It does not download assets, run compilers in images,
contact a registry, or publish images. Build the controller with Buoy 0.72 or a
compatible current SDK; historical SDK images are separate subjects under test.

```sh
mkdir -p local/releases-cli
buoy src/releases.bui -o local/releases-cli/buoy-releases
./local/releases-cli/buoy-releases verify catalog/releases.json --expect-releases 88
```

No Python, ProcessKit, or external package is needed by this executable. Its
runtime uses the SDK's JSON, file, byte, and date facilities.

## Included history

The [catalog](../catalog/releases.json) records the official
[stretched-out-software/buoy-releases](https://github.com/stretched-out-software/buoy-releases/releases)
metadata captured from the beginning of that repository's release history:

| Item | Snapshot |
| --- | --- |
| Releases | 88 |
| Assets | 393 |
| Oldest release | `buoy-2026.06.19`, published June 20, 2026 |
| Latest release | `buoy-v0.72.0` |
| Assets by format | 65 DEB, 65 RPM, 66 EXE, 122 PKG, 22 DMG, 53 ZIP |
| Supplied API pages | One page of 88, requested page size 100 |
| Linux compiler plan | 65 Debian rows across 34 releases: 34 amd64 and 31 arm64 |
| Default SDK carrier plan | 88 rows, one preferred asset for every release |
| All-assets carrier plan | 393 rows |

The dated first tag is preserved exactly and has `version: null`; a version is
never invented from a date or asset filename. Release `buoy-v0.50.0` is Mac-only:
it gets an SDK carrier and no Linux compiler row. Debug-stub ZIPs remain in the
catalog with unknown OS/architecture when their names do not identify either.
No Linux artifact is invented for the 54 releases without a supported Debian
package. If a future release has no assets, it is retained and the matrix records
why no carrier can be produced.

## Capture and ingest

Capture all public API pages using an independently configured GitHub client:

```sh
mkdir -p local/release-input
# This command fetches metadata only; it does not download SDK installers.
gh api 'repos/stretched-out-software/buoy-releases/releases?per_page=100' \
  --paginate --slurp > local/release-input/pages.json
./local/releases-cli/buoy-releases ingest local/release-input/pages.json \
  --expect-releases 88 --expect-pages 1 --page-size 100 \
  --output catalog/releases.json
```

The expected counts above describe the included snapshot. Review new upstream
metadata and update those assertions when the upstream release count changes.
`--repository OWNER/REPO` selects another source; the default is the official
repository above. The tool checks each download URL against that exact repository,
release tag, and percent-encoded asset filename, and validates a release's
`html_url` when provided.

Accepted input forms are a GitHub API page array, an array of page arrays
(`gh api --paginate --slurp`), one compact API page per JSONL line, or one release
object per JSONL line. Use `-` as the input filename to read standard input. Input
is limited to 64 MiB. Empty files and mixtures of page arrays with standalone
release objects are rejected.

`--page-size` accepts GitHub page sizes 1–100. Every nonterminal supplied page must
be full, and the final page must be short. If the final nonempty page is full,
include the next empty page to demonstrate termination. `--expect-pages` and
`--expect-releases` must match the supplied capture exactly. Flattened release
JSONL supports the release-count assertion but cannot claim page verification.
The public snapshot was generated from the actual paginated API capture, not
from a reconstructed pagination envelope.

These checks validate the supplied capture's shape, counts, and origin fields;
they are not an independent live-network census. Keep the raw response privately
when maintaining the catalog. Output has no current-time generation stamp and is
ordered by publication timestamp and exact tag, with assets ordered by exact
name, so repeating ingestion or reordering the same records is deterministic.

The tool rejects duplicate release tags, asset names within a release, duplicate
asset URLs, missing/malformed GitHub `sha256:` digests, invalid sizes or dates,
non-boolean release flags, unsafe asset filenames, and source-origin mismatches.
It also rejects colliding sanitized image tags instead of silently merging
releases. Safe image tags are lowercase ASCII and are checked against Docker's
length limit; the original release tag remains separate and unchanged.

## Normalized catalog

The root object is schema 1 with `source` and `releases`:

- `source`: repository/API origin, observed and asserted release counts, asset
  count, page sizes/counts, and separate `countVerified`/`paginationVerified` flags.
- Each release: exact `release`, nullable tag-derived SemVer `version`,
  `publishedAt`, `draft`, `prerelease`, safe `imageTag`, all `assets`,
  `preferredLinux`, `preferredSdk`, and `linuxCompilerAvailable`.
- Each asset: exact `name`, `url`, bare lowercase `sha256`, integer `size`,
  `format`, `os`, `arch`, and `classification: "filename-derived"`.

`os` is `linux`, `macos`, `windows`, or `unknown`; `arch` is `amd64`, `arm64`, or
`unknown`. Classification uses artifact names and formats, not binary inspection.
These labels do not prove architecture or execution. A `buoy-v` tag contributes
`version` only when its remainder is valid SemVer; the exact release tag is always
the primary identifier.

`verify` reconstructs canonical selection and checks counts, pagination receipts,
source URLs, hashes, classifications, ordering, and safe tags. A normalized
catalog changed by hand must continue to satisfy those invariants.

## Image plans

```sh
./local/releases-cli/buoy-releases matrix catalog/releases.json --profile compiler \
  --output local/compiler-matrix.json
./local/releases-cli/buoy-releases matrix catalog/releases.json --profile sdk \
  --output local/sdk-matrix.json
./local/releases-cli/buoy-releases matrix catalog/releases.json --profile sdk --all-assets \
  --output local/all-assets-matrix.json
```

The output is `{schema: 1, repository, kind, rows, coverage}`. Each flat row has:

| Field | Meaning |
| --- | --- |
| `release`, `version` | Exact release tag and nullable expected tag version |
| `asset`, `url`, `sha256`, `size`, `format` | Exact selected asset and digest pin |
| `os`, `arch` | Source artifact classification |
| `profile` | `linux-compiler` or `sdk-artifact` |
| `imageTag` | Safe tag component; no registry or image repository is assumed |
| `runnableCompiler` | Recipe intent, not a successful execution receipt |
| `reason` | Selection/execution boundary |
| `platform` | `linux/amd64` or `linux/arm64`, compiler rows only |

The compiler profile selects the first exact-name-sorted DEB per Linux
architecture. RPM and ZIP files remain cataloged; they are not silently treated
as supported Debian compiler recipes. Each excluded release has a reason.

The SDK profile chooses one asset per release. It prefers Linux DEB, RPM, then ZIP;
otherwise macOS PKG, ZIP, DMG; otherwise Windows EXE/ZIP; then other opaque assets.
Ties are resolved by exact filename, preferring Linux/Windows amd64 or macOS arm64.
`--all-assets` emits every asset instead. Its ordinal tag suffix is deterministic
within a catalog snapshot; bind published image tags to the catalog/checksum
rather than assuming ordinal stability if upstream assets later change.

SDK carriers store verified installer/archive bytes. In particular a macOS PKG
or Windows EXE in a Linux carrier is **not a native Docker compiler**. Every
carrier row has `runnableCompiler: false`. No source-artifact OS is reused as a
Docker platform. A compiler row means a supported Linux package exists; it still
needs an actual image build and native compiler/consumer execution.

`coverage` keeps `catalogReleases`, `catalogAssets`, `eligibleReleases`,
`plannedImages`, and exclusions separate. `builtImages` is null and
`nativeExecutionVerified` is false: catalog completeness is not image-build or
native-test coverage. Record real build results separately, including expired
SDKs, dependency failures, and differences between a release tag's expected
version and the compiler's reported version. Never rewrite catalog identity to
hide such a result.

The catalog and this repository's license do not grant redistribution rights to
SDK binaries or their third-party dependencies. Review upstream SDK terms and
bundled notices before publishing cached or derived images. This tool performs
no image or registry push.
