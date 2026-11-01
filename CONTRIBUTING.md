# Contributing to the native validation coordinator

Keep build execution separate from receipt validation and publication. Use Buoy
or BuoyScript for new tooling; small platform bootstrap scripts may locate the
compiler and invoke a private, operator-owned driver. Do not add Python wrappers.

Verify changed `.bui` files using the installed compiler, including each affected
conditional target branch. Build and exercise both successful and rejected input
cases. Report exact commands, compiler version, native host and observed results.

Test suites, fixtures, evidence, real host profiles and generated reports stay
local and ignored. Do not add credentials, internal connection details or private
test inputs to the repository. Never turn an unexpected skip into a passing check.

Privileged runners accept trusted default-branch manual requests only. Changes
must not register runners, arm desktop control, alter permissions, publish a
repository, or deploy a service as a side effect of validation.

Original code contributions are accepted under `MIT OR Apache-2.0`; prose uses
`CC-BY-4.0`. No CLA or DCO is required. Preserve your own authorship and applicable
upstream notices. See [LICENSING.md](LICENSING.md).
