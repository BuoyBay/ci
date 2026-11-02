# Contributing to the native validation coordinator

Keep build execution separate from receipt validation and publication. Use Buoy
or BuoyScript for new tooling; small platform bootstrap scripts may locate the
compiler and invoke a configured build driver. Do not add Python wrappers.

Verify changed `.bui` files using the installed compiler, including each affected
conditional target branch. Build and exercise both successful and rejected input
cases. Report exact commands, compiler version, native host and observed results.

Keep credentials out of source and image contexts. Never turn an unexpected
skip into a passing check.

Privileged runners accept trusted default-branch manual requests only. Preserve
that boundary when changing workflow triggers or runner selection.

Original code contributions are accepted under `MIT OR Apache-2.0`; prose uses
`CC-BY-4.0`. No CLA or DCO is required. Preserve your own authorship and applicable
upstream notices. See [LICENSING.md](LICENSING.md).
