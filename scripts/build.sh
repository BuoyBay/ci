#!/usr/bin/env bash
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")
compiler=${BUOY_COMPILER:-buoy}
build_dir=${BUOY_CI_BUILD_DIR:-"$repo_root/local/bin"}
if ! command -v -- "$compiler" >/dev/null 2>&1 && [[ ! -x "$compiler" ]]; then
  printf 'Set BUOY_COMPILER to an installed native Buoy compiler executable.\n' >&2
  exit 1
fi
mkdir -p -- "$build_dir"
"$compiler" "$repo_root/src/main.bui" -o "$build_dir/buoy-ci"
printf 'Built %s\n' "$build_dir/buoy-ci"
