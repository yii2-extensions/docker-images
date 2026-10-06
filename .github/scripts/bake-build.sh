#!/usr/bin/env bash
# Builds every bake target of one family for one PHP version on one platform in a single invocation.
#
# Usage: .github/scripts/bake-build.sh <smoke|digest>
#
# smoke   builds the images and runs their smoke-test stage (nothing is exported but build cache).
# digest  pushes the images by digest and writes the bake metadata file BAKE_METADATA_FILE.
#
# Environment:
#   BAKE_PHP            PHP version, as in the PHP_VERSION build arg (for example `8.5`).
#   BAKE_PLATFORM       Target platform (for example `linux/arm64`).
#   BAKE_CACHE_WRITE    `true` to export the registry build cache from the `full` target (smoke only).
#   BAKE_METADATA_FILE  Metadata file to write (digest only).
#   IMAGE, VERSION, CREATED, REVISION are read by docker-bake.hcl itself.
set -euo pipefail

docker_bin="${DOCKER:-docker}"
mode="${1:-}"

die() {
    printf '::error::%s\n' "$1" >&2
    exit 1
}

[[ "$mode" == smoke || "$mode" == digest ]] || die "Usage: $0 <smoke|digest>"
: "${BAKE_PHP:?BAKE_PHP is required}" "${BAKE_PLATFORM:?BAKE_PLATFORM is required}" "${IMAGE:?IMAGE is required}"

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

if [[ "$mode" == smoke && "${BAKE_CACHE_WRITE:-false}" == true ]]; then
    if [[ -n "$full_target" ]]; then
        args+=(--set "${full_target}.cache-to=type=registry,ref=${cache_ref},mode=max,image-manifest=true,oci-mediatypes=true")
    else
        printf '::warning::No full target for PHP %s; build cache is not exported.\n' "$BAKE_PHP"
    fi
fi

if [[ "$mode" == digest ]]; then
    : "${BAKE_METADATA_FILE:?BAKE_METADATA_FILE is required in digest mode}"
    mkdir -p "$(dirname "$BAKE_METADATA_FILE")"
    args+=(--metadata-file "$BAKE_METADATA_FILE")
fi

printf 'bake %s on %s (cache %s): %s\n' "$mode" "$BAKE_PLATFORM" "$cache_ref" "${targets[*]}"
"$docker_bin" "${args[@]}" "${targets[@]}"

if [[ "$mode" == digest ]]; then
    for target in "${targets[@]}"; do
        digest="$(jq -r --arg t "$target" '.[$t]["containerimage.digest"] // empty' "$BAKE_METADATA_FILE")"
        [[ "$digest" == sha256:* ]] || die "No digest recorded for ${target}."
        printf '%s %s@%s\n' "$target" "$IMAGE" "$digest"
    done
fi
