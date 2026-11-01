#!/usr/bin/env bash
# Build local images from a normalized, checksum-pinned public release matrix.
set -euo pipefail
umask 077
ci_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
matrix=
output="$ci_root/local/images"
cache="$ci_root/local/releases/assets"
tag_prefix=buoy-ci
jobs=4
command_timeout=900
release_filter=
arch_filter=any
base_image=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
usage() {
    printf '%s\n' 'Usage: scripts/images.sh --matrix FILE [--output DIR] [--cache DIR] [--jobs N] [--command-timeout SECONDS] [--tag-prefix NAME] [--release TAG] [--arch amd64|arm64|any] [--base-image REF]'
}
while (($#)); do
    case "$1" in
        --matrix) matrix=$2; shift 2 ;;
        --output) output=$2; shift 2 ;;
        --cache) cache=$2; shift 2 ;;
        --jobs) jobs=$2; shift 2 ;;
        --command-timeout) command_timeout=$2; shift 2 ;;
        --tag-prefix) tag_prefix=$2; shift 2 ;;
        --release) release_filter=$2; shift 2 ;;
        --arch) arch_filter=$2; shift 2 ;;
        --base-image) base_image=$2; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ -f "$matrix" ]] || { printf 'Matrix file required.\n' >&2; exit 2; }
[[ "$jobs" =~ ^[1-9][0-9]*$ && "$jobs" -le 16 ]] || { printf 'Jobs must be 1..16.\n' >&2; exit 2; }
[[ "$tag_prefix" =~ ^[a-z0-9][a-z0-9._/-]*$ ]] || { printf 'Invalid local tag prefix.\n' >&2; exit 2; }
for command_name in jq curl docker sha256sum; do command -v "$command_name" >/dev/null; done
[[ "$command_timeout" =~ ^[0-9]+$ && "$command_timeout" -ge 30 && "$command_timeout" -le 7200 ]] || { printf 'Command timeout must be 30..7200 seconds.\n' >&2; exit 2; }
timeout_program=$(command -v timeout || command -v gtimeout || true)
[[ -n "$timeout_program" ]] || { printf 'GNU timeout (or gtimeout) is required.\n' >&2; exit 2; }
bounded_docker() { "$timeout_program" --foreground --kill-after=30s "${command_timeout}s" docker "$@"; }
jq -e '.schema == 1 and (.rows | type == "array") and (.repository | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))' "$matrix" >/dev/null
[[ "$arch_filter" == any || "$arch_filter" == amd64 || "$arch_filter" == arm64 ]] || { printf 'Arch must be any, amd64 or arm64.\n' >&2; exit 2; }
repository=$(jq -r .repository "$matrix")
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
runner_fingerprint=$(sha256sum "$0" | cut -d' ' -f1)
mkdir -p "$output" "$cache" "$output/records" "$output/logs" "$output/contexts"
output=$(CDPATH= cd -- "$output" && pwd)
cache=$(CDPATH= cd -- "$cache" && pwd)
if ! mkdir "$output/.run.lock" 2>/dev/null; then
    printf 'Output directory already has a run lock; choose another output or inspect the interrupted run.\n' >&2
    exit 2
fi
trap 'rmdir "$output/.run.lock" 2>/dev/null || true' EXIT
recipe_dir=$(mktemp -d "$output/recipes.XXXXXX")
mkdir "$recipe_dir/bin" "$recipe_dir/linux" "$recipe_dir/sdk"
cp "$ci_root/images/bin/buoy" "$recipe_dir/bin/buoy"
cp "$ci_root/images/bin/inspect-toolchain" "$recipe_dir/bin/inspect-toolchain"
cp "$ci_root/images/bin/configure-compatibility" "$recipe_dir/bin/configure-compatibility"
cp "$ci_root/images/compatibility.json" "$recipe_dir/compatibility.json"
cp "$ci_root/images/linux/Dockerfile" "$recipe_dir/linux/Dockerfile"
cp "$ci_root/images/sdk/Dockerfile" "$recipe_dir/sdk/Dockerfile"
recipe_fingerprint=$(cd "$recipe_dir" && sha256sum linux/Dockerfile sdk/Dockerfile bin/buoy bin/inspect-toolchain bin/configure-compatibility compatibility.json | sha256sum | cut -d' ' -f1)
rows="$output/selected-rows.jsonl"
jq -c --arg release "$release_filter" --arg arch "$arch_filter" '.rows[] | select(($release == "" or .release == $release) and ($arch == "any" or .arch == $arch))' "$matrix" > "$rows"
[[ -s "$rows" ]] || { printf 'No matrix rows selected.\n' >&2; exit 2; }

fetch_asset() {
    local row=$1 sha url file lock attempt=0
    sha=$(jq -r .sha256 <<< "$row")
    url=$(jq -r .url <<< "$row")
    file="$cache/$sha"
    lock="$cache/$sha.lock"
    while ! mkdir "$lock" 2>/dev/null; do
        if [[ -f "$file" && ! -L "$file" ]] && printf '%s  %s\n' "$sha" "$file" | sha256sum --check --status -; then return; fi
        ((attempt+=1))
        ((attempt < 600)) || { printf 'Asset lock timeout: %s\n' "$sha" >&2; return 1; }
        sleep 1
    done
    if [[ -f "$file" && ! -L "$file" ]] && printf '%s  %s\n' "$sha" "$file" | sha256sum --check --status -; then
        rmdir "$lock"
        return
    fi
    local temporary
    temporary=$(mktemp "$cache/.download.XXXXXX")
    if ! curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 30 --max-time 1800 --output "$temporary" "$url"; then
        rm -f "$temporary"; rmdir "$lock"; return 1
    fi
    if ! printf '%s  %s\n' "$sha" "$temporary" | sha256sum --check --strict -; then
        rm -f "$temporary"; rmdir "$lock"; return 1
    fi
    mv -f "$temporary" "$file"
    rmdir "$lock"
}

build_row() (
    set -euo pipefail
    local row=$1
    local release sha url profile arch os format version image_tag tag key context started container_id= archive_tag= archive_id= reported_version= raw_version_exit=-1 identity_match=false behavior_status=not-run behavior_exit=-1 compatibility='{}' compat_root=
    release=$(jq -r .release <<< "$row")
    sha=$(jq -r .sha256 <<< "$row")
    url=$(jq -r .url <<< "$row")
    profile=$(jq -r .profile <<< "$row")
    arch=$(jq -r .arch <<< "$row")
    os=$(jq -r .os <<< "$row")
    format=$(jq -r .format <<< "$row")
    version=$(jq -r '.version // ""' <<< "$row")
    image_tag=$(jq -r .imageTag <<< "$row")
    [[ "$sha" =~ ^[a-f0-9]{64}$ && "$image_tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]
    [[ "$url" == "https://github.com/$repository/releases/download/"* ]]
    [[ "$profile" == linux-compiler || "$profile" == sdk-artifact ]]
    tag="$tag_prefix:$image_tag"
    key=$(printf '%s\n%s\n%s\n%s\n%s\n' "$release" "$profile" "$sha" "$image_tag" "$(jq -r .asset <<< "$row")" | sha256sum | cut -d' ' -f1)
    if [[ "$profile" == linux-compiler ]]; then
        compatibility=$(jq -c --arg sha "$sha" '(.assets[$sha] // {})' "$recipe_dir/compatibility.json")
    fi
    compat_root=$(jq -r '.producerRoot // ""' <<< "$compatibility")
    context=$(mktemp -d "$output/contexts/$key.XXXXXX")
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cleanup_record() {
        local status=$?
        trap - EXIT
        if [[ -n "$container_id" ]]; then bounded_docker rm -f "$container_id" >/dev/null 2>&1 || true; fi
        for cid_file in "$context"/*.cid; do
            [[ -f "$cid_file" ]] || continue
            own_container=$(cat "$cid_file")
            if [[ "$own_container" =~ ^[a-f0-9]{64}$ ]]; then bounded_docker rm -f "$own_container" >/dev/null 2>&1 || true; fi
        done
        local image_id= category=
        if ((status != 0)); then
            if ((status == 124 || status == 137)); then category=command-timeout
            elif grep -Eq 'beta build.*expired|beta.*expired' "$output/logs/$key.log"; then category=expired-upstream-beta
            elif grep -Fq 'Version mismatch:' "$output/logs/$key.log"; then category=upstream-version-mismatch
            else category=build-or-runtime-failure; fi
        fi
        if ((status == 0)); then image_id=$(bounded_docker image inspect "$tag" --format '{{.Id}}'); fi
        jq -n --argjson source "$row" --argjson deploymentCompatibility "$compatibility" --arg runId "$run_id" --arg recipeFingerprint "$recipe_fingerprint" --arg runnerFingerprint "$runner_fingerprint" --arg tag "$tag" --arg imageId "$image_id" --arg archiveImage "$archive_tag" --arg archiveImageId "$archive_id" --arg reportedVersion "$reported_version" --argjson rawVersionExitCode "$raw_version_exit" --argjson identityMatch "$identity_match" --arg behaviorStatus "$behavior_status" --argjson behaviorExitCode "$behavior_exit" --arg failureCategory "$category" --arg started "$started" --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson exitCode "$status" --arg log "$output/logs/$key.log" \
            '{schema:1,runId:$runId,recipeFingerprint:$recipeFingerprint,runnerFingerprint:$runnerFingerprint,source:$source,deploymentCompatibility:$deploymentCompatibility,image:$tag,imageId:$imageId,archiveImage:$archiveImage,archiveImageId:$archiveImageId,compilerChecks:(if $source.profile=="linux-compiler" then {reportedVersion:$reportedVersion,rawVersionExitCode:$rawVersionExitCode,identityMatch:$identityMatch,behaviorStatus:$behaviorStatus,behaviorExitCode:$behaviorExitCode} else null end),failureCategory:(if $failureCategory=="" then null else $failureCategory end),started:$started,finished:$finished,exitCode:$exitCode,status:(if $exitCode==0 then "passed" else "failed" end),log:$log}' > "$output/records/$key.json.staging"
        mv "$output/records/$key.json.staging" "$output/records/$key.json"
        if ((status == 0)); then rm -rf -- "$context"; fi
        printf '%s %s %s\n' "$([[ $status == 0 ]] && printf PASS || printf FAIL)" "$release" "$profile"
        exit "$status"
    }
    trap cleanup_record EXIT
    exec > >(tee "$output/logs/$key.log") 2>&1
    fetch_asset "$row"
    ln "$cache/$sha" "$context/payload" 2>/dev/null || cp "$cache/$sha" "$context/payload"
    printf '%s\n' "$row" > "$context/manifest.json"
    local dockerfile platform
    if [[ "$profile" == linux-compiler ]]; then
        [[ "$os" == linux && "$format" == deb && ( "$arch" == amd64 || "$arch" == arm64 ) ]]
        platform="linux/$arch"
        mkdir "$context/bin"
        cp "$recipe_dir/bin/buoy" "$context/bin/buoy"
        cp "$recipe_dir/bin/inspect-toolchain" "$context/bin/inspect-toolchain"
        cp "$recipe_dir/bin/configure-compatibility" "$context/bin/configure-compatibility"
        printf '%s\n' "$compatibility" > "$context/compatibility.json"
        dockerfile="$recipe_dir/linux/Dockerfile"
    else
        platform=linux/amd64
        dockerfile="$recipe_dir/sdk/Dockerfile"
    fi
    local -a build=("$timeout_program" --foreground --kill-after=30s "${command_timeout}s" docker buildx build --load --platform "$platform" --file "$dockerfile" --build-arg "BASE_IMAGE=$base_image" --build-arg "SHA256=$sha" --build-arg "COMPAT_BUILD_ROOT=$compat_root" --build-arg "RELEASE=$release" --build-arg "VERSION=$version" --build-arg "ASSET=$(jq -r .asset <<< "$row")" --build-arg "SDK_OS=$os" --build-arg "SDK_ARCH=$arch")
    jq -nc --args '$ARGS.positional' -- "${build[@]}" "$context" > "$output/logs/$key.command.json"
    if [[ "$profile" == linux-compiler ]]; then
        archive_tag="$tag-archive"
        "${build[@]}" --target archive --tag "$archive_tag" "$context"
        archive_id=$(bounded_docker image inspect "$archive_tag" --format '{{.Id}}')
        if bounded_docker run --rm --cidfile "$context/raw-version.cid" --platform "$platform" "$archive_tag" buoy --version > "$output/logs/$key.version.log" 2>&1; then
            raw_version_exit=0
        else
            raw_version_exit=$?
        fi
        reported_version=$(tr '[:space:]' '\n' < "$output/logs/$key.version.log" | grep -E '^[0-9]+([.][0-9]+){1,2}(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?$' | head -n 1 || true)
        if [[ -n "$version" && "$reported_version" == "$version" && "$raw_version_exit" == 0 ]]; then identity_match=true; fi
        if bounded_docker run --rm --cidfile "$context/behavior.cid" --platform "$platform" "$archive_tag" /usr/local/libexec/inspect-toolchain > "$output/logs/$key.behavior.log" 2>&1; then
            behavior_status=passed
            behavior_exit=0
        else
            behavior_exit=$?
            if grep -Eq 'beta build.*expired|beta.*expired' "$output/logs/$key.behavior.log"; then
                behavior_status=blocked-upstream-expiry
            else
                behavior_status=failed
                if ((behavior_exit == 124 || behavior_exit == 137)); then behavior_status=timed-out; fi
            fi
        fi
        "${build[@]}" --target verified --tag "$tag" "$context"
    else
        "${build[@]}" --tag "$tag" "$context"
    fi
    if [[ "$profile" == linux-compiler ]]; then
        bounded_docker run --rm --cidfile "$context/verified-version.cid" --platform "$platform" "$tag" buoy --version
        bounded_docker run --rm --cidfile "$context/verified-behavior.cid" --platform "$platform" "$tag" /usr/local/libexec/inspect-toolchain "$version"
    else
        container_id=$(bounded_docker create --entrypoint /artifact-not-executed "$tag")
        bounded_docker cp "$container_id:/sdk/payload" "$context/recovered"
        printf '%s  %s\n' "$sha" "$context/recovered" | sha256sum --check --strict -
        bounded_docker cp "$container_id:/sdk/release.json" "$context/recovered.json"
        jq -e --arg sha "$sha" '.sha256 == $sha' "$context/recovered.json" >/dev/null
        bounded_docker rm "$container_id" >/dev/null
        container_id=
    fi
)

pids=()
failed=0
while IFS= read -r row; do
    build_row "$row" &
    pids+=("$!")
    if ((${#pids[@]} >= jobs)); then
        if ! wait "${pids[0]}"; then failed=1; fi
        if ((${#pids[@]} > 1)); then
            pids=("${pids[@]:1}")
        else
            pids=()
        fi
    fi
done < "$rows"
for worker_pid in ${pids[@]+"${pids[@]}"}; do
    if ! wait "$worker_pid"; then failed=1; fi
done
selected_records="$output/selected-records.jsonl"
: > "$selected_records"
while IFS= read -r row; do
    key=$(printf '%s\n%s\n%s\n%s\n%s\n' "$(jq -r .release <<< "$row")" "$(jq -r .profile <<< "$row")" "$(jq -r .sha256 <<< "$row")" "$(jq -r .imageTag <<< "$row")" "$(jq -r .asset <<< "$row")" | sha256sum | cut -d' ' -f1)
    if [[ -f "$output/records/$key.json" ]] && jq -e --arg runId "$run_id" '.runId == $runId' "$output/records/$key.json" >/dev/null; then
        jq -c . "$output/records/$key.json" >> "$selected_records"
    else
        failed=1
        jq -nc --argjson source "$row" --arg runId "$run_id" '{schema:1,runId:$runId,source:$source,status:"missing-record",exitCode:1}' >> "$selected_records"
    fi
done < "$rows"
jq -s --arg runId "$run_id" '{schema:1,runId:$runId,records:.,passed:([.[]|select(.status=="passed")]|length),failed:([.[]|select(.status!="passed")]|length)}' "$selected_records" > "$output/summary.json"
exit "$failed"
