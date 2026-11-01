# Build Buoy projects and historical compiler images

This reusable engine gives Linux, macOS and Windows validation a shared
receipt format and a native publication gate. Build/test drivers and their suites
remain outside Git. The gate requires actual native build and behavior receipts
for the exact planned Git revisions; missing, failed, skipped, duplicated, stale
or mismatched results fail closed. Each project's trusted plan controls its
license approval, required checks, publication visibility and hold status.

The engine, workflow and templates are public source. Real test suites, evidence,
host profiles, connection details and credentials stay private outside Git.

It does not push code, change repository visibility, deploy services, register
runners or change desktop permissions.

## Build and use

Install Buoy, then compile the coordinator into its isolated local directory:

```sh
./scripts/build.sh
./local/bin/buoy-ci host
./local/bin/buoy-ci preflight /absolute/path/to/private/profile.json
./local/bin/buoy-ci manifest /absolute/path/to/private/plan.json
./local/bin/buoy-ci gate /absolute/path/to/private/plan.json /absolute/path/to/private/report.json
```

Set `BUOY_COMPILER` to an executable path when it is not on `PATH`. Windows can
use `./scripts/build.ps1` and `local/bin/buoy-ci.exe`. The coordinator uses only
Buoy's built-in JSON/filesystem facilities; no Python or SDK packages are needed.
The Windows bootstrap copies matching runtime DLLs from the compiler install and
runs the resulting executable. Set `BUOY_RUNTIME_DIR` explicitly for a custom SDK
layout; an absent runtime is a build failure rather than a successful unusable
output.

Copy the files in [config/](config/) into ignored `local/` or another private
directory. Replace the example zero revisions and run ID before use. Set each
repository's real `codeLicense` and explicitly approve it with `licenseApproved`
only after the project owner has decided its publication terms. A public
repository cannot be held or have an unapproved license. The engine does not
infer permission from a project name or interpret custom license text. A native
host profile names installed compiler/packager files, SDK packages and private
suite directories. Preflight checks the local native host and configured paths.
It does not establish compiler provenance or execute the test suite.

Plan names/check IDs use canonical lowercase identifiers (`a-z`, digits, `-`,
`_`, `.`, `/`); repository names omit `/`. Use complete lowercase Git object IDs.
The private collector associates these receipt IDs with actual source checkouts.

## Run private suites

Configure `BUOY_CI_PLAN`, `BUOY_CI_PROFILE`, `BUOY_PRIVATE_DRIVER` and
`BUOY_CI_REPORTS_DIR` as absolute paths, then invoke `./scripts/run-private.sh`.
The output directory must be new. The operator-owned driver receives exactly
`PLAN_PATH REPORT_DIRECTORY`; it may coordinate authorized native hosts and must
write report bundles with relative, nonempty evidence files. A nonzero driver
exit stops the run before gate evaluation. The wrapper captures each stage's
output and full gate result in hidden `.ci-*` files inside the private evidence
directory. It prints only a generic pass/fail status, so private suite output
does not enter public Actions logs. Nothing is uploaded automatically.

The trusted driver must check the source revision and clean tree before building,
record actual command exits and native host identity, and retain compiler/runtime
versions, source/artifact hashes and logs. Gate receipts are trusted collector
claims, not cryptographic attestations. A pass authorizes no external action by
itself; publication remains a separate explicit operation after all required
results and project holds are reviewed.

## CI runner boundary

[The workflow](.github/workflows/native-gate.yml) runs only a trusted manual
default-branch dispatch on an operator-provisioned coordinator. Reusable calls
must originate from that same trusted dispatch context. Pull requests cannot run
private suites on privileged hosts. Runner installation, host profiles, SSH trust,
secrets and desktop access are provisioned separately. No schedules are enabled.

Other organizations and forks can reuse the engine without source changes. Pin
the same immutable engine commit in the reusable workflow reference and checkout:

```yaml
on: workflow_dispatch
jobs:
  native:
    uses: your-org/ci/.github/workflows/native-gate.yml@FULL_COMMIT_SHA
    with:
      engine_repository: your-org/ci
      engine_ref: FULL_COMMIT_SHA
```

The caller must configure the `buoy-ci-coordinator` self-hosted runner label and
its private environment. Runner-group access remains the operator's boundary;
this workflow does not grant other repositories access to a runner.

The workflow definition is scaffolding; a hosted GitHub run is not claimed.
Private Mac/Windows workers can use the same native receipt validator, with their
own isolated build directories and authorized existing desktop sessions.

## Historical SDK images

A native catalog tool covers all 88 upstream releases and their 393 assets. Shared
Docker recipes build Linux compiler environments and SDK artifact carriers, with
asset checksums verified before use. The carrier profile also preserves early
Mac-only releases for extraction on native workers.

```sh
mkdir -p local/releases-cli
buoy src/releases.bui -o local/releases-cli/buoy-releases
./local/releases-cli/buoy-releases verify catalog/releases.json
./local/releases-cli/buoy-releases matrix catalog/releases.json --profile sdk --output local/sdk.json
./scripts/images.sh --matrix local/sdk.json --jobs 4
```

See [image recipes and usage](docs/RELEASE_IMAGES.md) and
[catalog maintenance](docs/RELEASE_CATALOG.md). Archived SDK identity, actual
compiler behavior, and strict release-version verification are separate results.
Expired SDKs and upstream version mismatches remain explicit. Images stay local;
there is no registry-push operation. The upstream SDK retains its own license.

## Local AI setup

On your own machine, run `buoy ai init --both` after cloning. Generated agent
instructions, documentation indexes and editor settings remain local and ignored.

See [CONTRIBUTING.md](CONTRIBUTING.md), [LICENSING.md](LICENSING.md) and
[PYTHON.md](PYTHON.md) for contribution, license and dependency policies.
