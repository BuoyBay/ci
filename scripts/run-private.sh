#!/usr/bin/env bash
set -euo pipefail
umask 077
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")
: "${BUOY_CI_PLAN:?Set an absolute private plan path}"
: "${BUOY_CI_PROFILE:?Set an absolute private native-host profile path}"
: "${BUOY_PRIVATE_DRIVER:?Set an absolute executable private validation driver path}"
: "${BUOY_CI_REPORTS_DIR:?Set a new private evidence/output directory}"
for required in "$BUOY_CI_PLAN" "$BUOY_CI_PROFILE" "$BUOY_PRIVATE_DRIVER" "$BUOY_CI_REPORTS_DIR"; do
  case "$required" in /*) ;; *) printf 'Private CI paths must be absolute.\n' >&2; exit 1 ;; esac
done
if [[ ! -x "$BUOY_PRIVATE_DRIVER" ]]; then
  printf 'Private validation driver is not executable.\n' >&2
  exit 1
fi
if [[ -e "$BUOY_CI_REPORTS_DIR" ]]; then
  printf 'Refusing an existing evidence directory; use a fresh run directory.\n' >&2
  exit 1
fi
mkdir -m 700 -- "$BUOY_CI_REPORTS_DIR"
private_step() {
  local label=$1
  shift
  local status=0
  "$@" > "$BUOY_CI_REPORTS_DIR/.ci-$label.log" 2>&1 || status=$?
  if (( status != 0 )); then
    printf 'Native validation stage %s failed (exit %s); detailed output remains private.\n' "$label" "$status" >&2
    return "$status"
  fi
}
private_step build "$script_dir/build.sh"
binary=${BUOY_CI_BUILD_DIR:-"$repo_root/local/bin"}/buoy-ci
private_step preflight "$binary" preflight "$BUOY_CI_PROFILE"
private_step manifest "$binary" manifest "$BUOY_CI_PLAN"
private_step driver "$BUOY_PRIVATE_DRIVER" "$BUOY_CI_PLAN" "$BUOY_CI_REPORTS_DIR"
shopt -s nullglob
shopt -u dotglob failglob
reports=("$BUOY_CI_REPORTS_DIR"/*.json)
if (( ${#reports[@]} == 0 )); then
  printf 'Private driver produced no report bundles.\n' >&2
  exit 1
fi
gate_status=0
"$binary" gate "$BUOY_CI_PLAN" "${reports[@]}" > "$BUOY_CI_REPORTS_DIR/.ci-gate.json" 2> "$BUOY_CI_REPORTS_DIR/.ci-gate-error.log" || gate_status=$?
if (( gate_status != 0 )); then
  printf 'Native validation gate failed (exit %s); detailed output remains private.\n' "$gate_status" >&2
  exit "$gate_status"
fi
printf 'Native validation gate passed; detailed reports remain private.\n'
