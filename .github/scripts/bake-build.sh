#!/usr/bin/env bash
# Builds every bake target of one family for one PHP version on one platform in a single invocation.
#
# Usage: .github/scripts/bake-build.sh <smoke|digest>
#
# smoke   builds the images, then runs their smoke-test stage (nothing is exported but build cache).
# digest  pushes the images by digest and writes the bake metadata file BAKE_METADATA_FILE.
#
# Building and pushing are retried, so a transient network failure (PECL, Debian mirrors, registries) does not fail
# the job; BuildKit keeps the completed layers and runs a failed step again from a clean snapshot. The smoke stage
# runs once, after the images are built, and is never retried: a failing smoke test fails the script.
#
# Environment:
#   BAKE_PHP            PHP version, as in the PHP_VERSION build arg (for example `8.5`).
#   BAKE_PLATFORM       Target platform (for example `linux/arm64`).
#   BAKE_CACHE_WRITE    `true` to export the registry build cache of the `full` image (smoke only, with the build).
#   BAKE_METADATA_FILE  Metadata file to write (digest only).
#   BAKE_ATTEMPTS       Attempts for the build (smoke) or the push (digest), default 3.
#   BAKE_RETRY_DELAY    Seconds before the first retry, doubled for each further retry, default 30.
#   IMAGE, VERSION, CREATED, REVISION are read by docker-bake.hcl itself.
set -euo pipefail

docker_bin="${DOCKER:-docker}"
mode="${1:-}"
attempts="${BAKE_ATTEMPTS:-3}"
retry_delay="${BAKE_RETRY_DELAY:-30}"

die() {
    printf '::error::%s\n' "$1" >&2
    exit 1
}

# Usage: bake_with_retry <description> <bake arguments...>
bake_with_retry() {
    local description="$1"
    shift
    local attempt delay="$retry_delay"
    for ((attempt = 1; ; attempt++)); do
        if "$docker_bin" "$@"; then
            return 0
        fi
        ((attempt < attempts)) || die "${description} failed after ${attempts} attempt(s)."
        printf '::warning::%s failed (attempt %d of %d); retrying in %ds.\n' "$description" "$attempt" "$attempts" "$delay"
        sleep "$delay"
        delay=$((delay * 2))
    done
}

[[ "$mode" == smoke || "$mode" == digest ]] || die "Usage: $0 <smoke|digest>"
: "${BAKE_PHP:?BAKE_PHP is required}" "${BAKE_PLATFORM:?BAKE_PLATFORM is required}" "${IMAGE:?IMAGE is required}"
[[ "$attempts" =~ ^[1-9][0-9]*$ ]] || die "BAKE_ATTEMPTS must be a positive integer (got '${attempts}')."
[[ "$retry_delay" =~ ^[0-9]+$ ]] || die "BAKE_RETRY_DELAY must be a non-negative integer (got '${retry_delay}')."

arch="${BAKE_PLATFORM#*/}"
arch="${arch//\//-}"
cache_ref="${IMAGE}:buildcache-${BAKE_PHP}-${arch}"

bake_json="$("$docker_bin" buildx bake --print "$mode")" || die "bake --print ${mode} failed."

mapfile -t targets < <(jq -r --arg php "$BAKE_PHP" \
    '.target | to_entries[] | select(.value.args.PHP_VERSION == $php) | .key' <<<"$bake_json" | sort)
[[ ${#targets[@]} -gt 0 ]] || die "No '${mode}' target for PHP ${BAKE_PHP}."

full_target="$(jq -r --arg php "$BAKE_PHP" \
    '.target | to_entries[] | select(.value.args.PHP_VERSION == $php and .value.args.BUILD_TYPE == "full") | .key' \
    <<<"$bake_json" | head -n 1)"

args=(buildx bake --provenance=false --sbom=false)
for target in "${targets[@]}"; do
    args+=(--set "${target}.platform=${BAKE_PLATFORM}" --set "${target}.cache-from=type=registry,ref=${cache_ref}")
done

printf 'bake %s on %s (cache %s): %s\n' "$mode" "$BAKE_PLATFORM" "$cache_ref" "${targets[*]}"

if [[ "$mode" == smoke ]]; then
    # Build: the same targets stopped at the Dockerfile `image` stage, so the smoke run below reuses every layer
    build_args=("${args[@]}")
    for target in "${targets[@]}"; do
        build_args+=(--set "${target}.target=image")
    done
    # The registry cache export is network I/O too, so it belongs to the retried build and never to the smoke run
    if [[ "${BAKE_CACHE_WRITE:-false}" == true ]]; then
        if [[ -n "$full_target" ]]; then
            build_args+=(--set "${full_target}.cache-to=type=registry,ref=${cache_ref},mode=max,image-manifest=true,oci-mediatypes=true")
        else
            printf '::warning::No full target for PHP %s; build cache is not exported.\n' "$BAKE_PHP"
        fi
    fi
    bake_with_retry "Build of PHP ${BAKE_PHP} on ${BAKE_PLATFORM}" "${build_args[@]}" "${targets[@]}"

    # Smoke: the full targets, run once; only the smoke stage itself is not in the build cache yet
    "$docker_bin" "${args[@]}" "${targets[@]}" ||
        die "Smoke tests failed for PHP ${BAKE_PHP} on ${BAKE_PLATFORM} (not retried)."
    exit 0
fi

: "${BAKE_METADATA_FILE:?BAKE_METADATA_FILE is required in digest mode}"
mkdir -p "$(dirname "$BAKE_METADATA_FILE")"
args+=(--metadata-file "$BAKE_METADATA_FILE")
# Pushing by digest is idempotent, so a partly pushed attempt is safe to repeat
bake_with_retry "Push of PHP ${BAKE_PHP} on ${BAKE_PLATFORM}" "${args[@]}" "${targets[@]}"

for target in "${targets[@]}"; do
    digest="$(jq -r --arg t "$target" '.[$t]["containerimage.digest"] // empty' "$BAKE_METADATA_FILE")"
    [[ "$digest" == sha256:* ]] || die "No digest recorded for ${target}."
    printf '%s %s@%s\n' "$target" "$IMAGE" "$digest"
done
