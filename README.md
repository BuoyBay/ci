# CI and native build gates

Validate native Linux, macOS and Windows builds against an exact Git revision,
then evaluate their results with a shared publication gate. A project's plan
sets its required checks, license approval, publication visibility and holds.
Missing, failed, skipped, duplicated, stale or mismatched results fail the gate.

Shared Docker recipes also build checksum-pinned compiler environments and SDK
artifact carriers from the upstream release catalog.

## Build the coordinator

Install Buoy, then run:

```sh
./scripts/build.sh
./local/bin/buoy-ci host
```

Set `BUOY_COMPILER` to an executable path when it is not on `PATH`. Windows uses
`./scripts/build.ps1` and `local/bin/buoy-ci.exe`. The Windows bootstrap deploys
matching runtime DLLs from the compiler installation; `BUOY_RUNTIME_DIR` selects
a custom SDK runtime directory.

The coordinator uses Buoy's built-in JSON and filesystem facilities.

## Configure a project

Start with the included templates:

```sh
mkdir -p local
cp config/profile.example.json local/profile.json
cp config/plan.example.json local/plan.json
cp config/report.example.json local/report.json
```

Update the profile with your native host, compiler, packager and SDK paths.
The `privateTests` field names the directory containing your test suites.
Preflight checks the host and configured paths:

```sh
./local/bin/buoy-ci preflight "$PWD/local/profile.json"
```

Replace the plan's sample repositories, zero revisions and run ID. Set each
repository's `codeLicense`, `licenseApproved`, visibility, hold state and required
checks. Public releases require an approved license and no active hold.

Use canonical lowercase plan names and check IDs (`a-z`, digits, `-`, `_`, `.`,
`/`); repository names omit `/`. Revisions must be complete lowercase Git object
IDs. Review the selected check matrix with:

```sh
./local/bin/buoy-ci manifest "$PWD/local/plan.json"
```

The report template illustrates one check result. Produce a result for every
planned check, using the plan's run ID, repository revision and host identity.
Each result records the command, exit status and a relative path to a nonempty
supporting file. Evaluate the reports with:

```sh
./local/bin/buoy-ci gate "$PWD/local/plan.json" "$PWD/local/report.json"
```

## Run your build driver

Set these environment variables to absolute paths:

| Variable | Value |
| --- | --- |
| `BUOY_CI_PLAN` | Your project plan |
| `BUOY_CI_PROFILE` | Your native-host profile |
| `BUOY_PRIVATE_DRIVER` | Your executable build and test driver |
| `BUOY_CI_REPORTS_DIR` | A new output directory for this run |

Then run `./scripts/run-private.sh`. The wrapper builds the coordinator, checks
preflight and plan inputs, invokes your driver, and evaluates its JSON reports.
The driver receives exactly `PLAN_PATH REPORT_DIRECTORY` and writes report
bundles as `*.json` in that directory. A nonzero driver exit fails the run.

The driver checks the source revision and clean tree before building, records
actual commands and native host identity, and retains compiler/runtime versions,
source/artifact hashes and logs. Gate receipts represent the collector's results;
the gate validates their consistency rather than authenticating those claims.

Stage output and the complete gate result are saved in `.ci-*` files in the
output directory. The Actions log receives a concise pass/fail status. A passing
gate is an input to your release process; publication is a separate step.

## Use GitHub Actions

[The workflow](.github/workflows/native-gate.yml) runs on a self-hosted Linux x64
coordinator labeled `buoy-ci-coordinator`. Configure the environment variables
above on that runner. Jobs accept default-branch manual dispatches; reusable
calls must originate from the same dispatch context.

Pin the same immutable engine commit in the reusable workflow reference and
checkout:

```yaml
on: workflow_dispatch
jobs:
  native:
    uses: your-org/ci/.github/workflows/native-gate.yml@FULL_COMMIT_SHA
    with:
      engine_repository: your-org/ci
      engine_ref: FULL_COMMIT_SHA
```

Configure runner-group access for the calling repositories. Your driver can
coordinate native Mac and Windows workers using the same receipt format.

## Historical SDK images

The catalog covers 88 upstream releases and 393 assets. Shared Docker recipes
build Linux compiler environments and SDK artifact carriers, verifying asset
checksums before use. Carriers also preserve early Mac-only releases for
extraction on native workers.

```sh
mkdir -p local/releases-cli
buoy src/releases.bui -o local/releases-cli/buoy-releases
./local/releases-cli/buoy-releases verify catalog/releases.json
./local/releases-cli/buoy-releases matrix catalog/releases.json --profile sdk --output local/sdk.json
./scripts/images.sh --matrix local/sdk.json --jobs 4
```

See [image recipes and usage](docs/RELEASE_IMAGES.md) and
[catalog maintenance](docs/RELEASE_CATALOG.md). Archived SDK identity, actual
compiler behavior and strict release-version verification are separate results.
Expired SDKs and upstream version mismatches remain explicit. The upstream SDK
retains its own license.

[Contributing](CONTRIBUTING.md) · [Licensing](LICENSING.md) · [Python policy](PYTHON.md)
