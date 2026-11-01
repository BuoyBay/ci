# Build images from the complete Buoy release history

The catalog records every upstream release and its actual assets. Shared recipes
use those exact asset URLs and SHA-256 digests; a version is not assumed to have
Linux installers just because a newer version does.

Two image profiles serve different purposes:

| Profile | Contents | Execution |
| --- | --- | --- |
| `linux-compiler` | Extracted Linux DEB, C toolchain, core runtime dependencies and a verified CLI wrapper | Native compilation and execution are checked before a verified tag is created |
| `sdk-artifact` | An unchanged upstream archive/installer plus its catalog row | Transport only; no default command and no implied Linux, macOS or Windows compiler execution |

Artifact carriers cover releases that only shipped macOS or Windows downloads.
They let native hosts retrieve a pinned installer without pretending it runs in a
Linux container. Every release with a downloadable asset can have a carrier; only eligible assets can have
a verified Linux compiler image.

## Generate matrices

Build the native release tool and generate matrices from the committed catalog:

```sh
mkdir -p local/releases-cli
buoy src/releases.bui -o local/releases-cli/buoy-releases
./local/releases-cli/buoy-releases verify catalog/releases.json
./local/releases-cli/buoy-releases matrix catalog/releases.json --profile compiler --output local/compiler.json
./local/releases-cli/buoy-releases matrix catalog/releases.json --profile sdk --output local/sdk.json
```

See [catalog maintenance](RELEASE_CATALOG.md) for fetching and verifying a fresh
inventory. The SDK matrix selects one preferred asset per release. Add
`--all-assets` to retain every published installer/archive instead.

## Build locally

The runner requires Bash, Docker Buildx, curl, jq, sha256sum, and GNU timeout (or gtimeout). Run from this
repository; the generated contexts, asset cache, logs and receipts stay ignored:

```sh
./scripts/images.sh --matrix local/compiler.json --arch amd64 --jobs 4
./scripts/images.sh --matrix local/sdk.json --jobs 4
```

Use `--release buoy-v0.72.0` for one release, `--output DIR` for a separate run,
`--cache DIR` to share checksum-verified downloads, `--command-timeout SECONDS`
for a finite Docker-command deadline (default: 900 seconds), and `--tag-prefix NAME` to
choose a local image namespace. The default prefix is `buoy-ci`.

Build ARM64 compiler images on a native ARM64 Docker engine with `--arch arm64`.
Cross-platform Buildx execution requires separately configured emulation. Keep
native and emulated results distinct; setting `--platform` alone is not native
execution evidence.

The runner constructs a new minimal build context containing only the verified
payload, catalog row and fixed helper scripts. It never sends this repository's
Git metadata, private profiles, tests, receipts or credentials as image context.
There is no registry-push operation.

## Archive and verified tags

For a compiler row, the runner first creates an `-archive` tag with the extracted
official SDK and `io.buoy.verification=not-verified`. It then builds a separate
verified target. A verified tag requires:

1. The complete reported compiler version matches the catalog version.
2. A new Buoy program compiles and prints its expected output.
3. Semantic checking succeeds.
4. A native C object can be passed through `--extra-obj` without losing the SDK
   startup object.
5. The same verification succeeds in a fresh container after image construction.

The wrapper first probes the unchanged upstream driver. Where a Linux package
cannot discover its bundled stubs/CRT, it supplies the driver's documented paths.
Checksum-keyed entries in `images/compatibility.json` also relocate SDK-owned
CRT/static runtime archives to historical producer paths where an official
package still references those paths. Only the exact listed asset digests receive
these in-image filesystem aliases; they are not arbitrary ABI substitutions.
The original compiler executable and archive bytes remain unchanged.

The image does not alter the compiler's license or expiry checks.

Archive diagnostics record the reported version and independent native behavior
separately. A version mismatch does not prevent collecting fresh compile/link/run
and custom-object results from the unchanged SDK. Those diagnostics cannot create
a verified tag: the exact release-identity check still must pass. Expired binaries
retain their natural failure; diagnostics do not bypass their refusal.

Some historical SDKs are expired beta builds; some official release assets report
a compiler version different from the release tag. Those cases retain their
archive/carrier images and receive failed release-identity or runtime
classifications, as applicable. They do not
receive a verified, usable-compiler claim. No clocks or compiler binaries are
changed to work around an upstream refusal.

## Results and reproducibility

Use a distinct output directory for concurrent runs; the runner refuses an
already-locked output. Each invocation writes `summary.json` for its selected rows and run identifier.
Per-row receipts include the official asset/digest, local image IDs, archive IDs,
recipe fingerprint, status, failure category, timestamps and log paths. Results
from earlier runs in the same output directory cannot count as current passes.
Private receipts and detailed logs are not part of the public repository.

The default Debian base is pinned by manifest digest. Debian security packages
are resolved at image-build time, so the records identify the resulting image;
the project does not claim every rebuild is byte-for-byte identical.

Repository licenses cover our original scripts and recipes. Buoy compiler, SDK
and runtime components retain their [upstream terms](https://github.com/stretched-out-software/buoy-releases/blob/main/LICENSE.md),
and local images preserve their notices. These commands build local images and
do not publish them to a registry. The CI repository's permissive source license
does not grant redistribution rights to the embedded SDK.
