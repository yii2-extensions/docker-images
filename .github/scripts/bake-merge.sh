#!/usr/bin/env bash
# Publishes multi-platform manifest lists from per-platform digests, tagging them with the tags of the `image-*` bake
# targets. Experimental PHP versions (PHP_BASE_TAG != PHP_VERSION) are never published.
#
# Usage: .github/scripts/bake-merge.sh
#
# Environment:
#   BAKE_DIGESTS_DIR  Directory with the bake metadata files written by `bake-build.sh digest`, one per platform.
#   BAKE_PLATFORMS    Space-separated platforms every stable target must have (for example `linux/amd64 linux/arm64`).
#   BAKE_ROLLING      `false` publishes only the frozen tags (those that exist only because VERSION is set).
#   BAKE_DRY_RUN      `true` prints the manifest lists without pushing them.
#   IMAGE, VERSION are read by docker-bake.hcl itself.
set -euo pipefail

docker_bin="${DOCKER:-docker}"

die() {
    printf '::error::%s\n' "$1" >&2
    exit 1
}

: "${IMAGE:?IMAGE is required}" "${BAKE_DIGESTS_DIR:?BAKE_DIGESTS_DIR is required}"
: "${BAKE_PLATFORMS:?BAKE_PLATFORMS is required}"
read -r -a platforms <<<"$BAKE_PLATFORMS"
rolling="${BAKE_ROLLING:-true}"
dry_run="${BAKE_DRY_RUN:-false}"
version="${VERSION:-}"

if [[ "$rolling" != true && -z "$version" ]]; then
    die "BAKE_ROLLING=false requires VERSION, otherwise there is nothing to publish."
fi

shopt -s nullglob
metadata_files=("$BAKE_DIGESTS_DIR"/*.json)
[[ ${#metadata_files[@]} -gt 0 ]] || die "No metadata file in ${BAKE_DIGESTS_DIR}."

# target name => list of digests, one per platform metadata file.
digests_json="$(jq -s '
    [.[] | to_entries[] | {key, digest: .value["containerimage.digest"]}]
    | group_by(.key) | map({key: .[0].key, value: [.[].digest]}) | from_entries
' "${metadata_files[@]}")"

image_json="$(VERSION="$version" "$docker_bin" buildx bake --print image)" || die "bake --print image failed."
rolling_json="$(VERSION='' "$docker_bin" buildx bake --print image)" || die "bake --print image failed."

# One line per stable target: name<TAB>space-separated tags.
plan="$(jq -r --argjson rolling "$rolling_json" --arg frozen_only "$([[ "$rolling" == true ]] && echo false || echo true)" '
    .target | to_entries[]
    | select(.value.args.PHP_BASE_TAG == .value.args.PHP_VERSION)
    | .key as $name
    | (.value.tags // []) as $tags
    | (if $frozen_only == "true" then $tags - ($rolling.target[$name].tags // []) else $tags end) as $publish
    | "\($name)\t\($publish | join(" "))"
' <<<"$image_json" | sort)"
[[ -n "$plan" ]] || die "No stable image target to publish."

# First pass: validate every target before anything is pushed, so a missing digest never yields a partial release.
targets=()
tag_lines=()
digest_lines=()
while IFS=$'\t' read -r target tags; do
    [[ -n "$tags" ]] || die "No tag to publish for ${target}."
    digest_target="digest-${target#image-}"
    mapfile -t digests < <(jq -r --arg t "$digest_target" '.[$t] // [] | unique | .[]' <<<"$digests_json")

    if [[ ${#digests[@]} -ne ${#platforms[@]} ]]; then
        die "${digest_target}: expected ${#platforms[@]} platform digests (${platforms[*]}), found ${#digests[@]}."
    fi
    for digest in "${digests[@]}"; do
        [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "${digest_target}: invalid digest '${digest}'."
    done

    targets+=("$target")
    tag_lines+=("$tags")
    digest_lines+=("${digests[*]}")
done <<<"$plan"

# Second pass: publish.
expected="$(printf '%s\n' "${platforms[@]}" | sort | paste -sd ' ')"
summary="## Published images"$'\n\n'"| Target | Tags | Digests |"$'\n'"| --- | --- | --- |"$'\n'

for i in "${!targets[@]}"; do
    read -r -a tag_list <<<"${tag_lines[$i]}"
    read -r -a digests <<<"${digest_lines[$i]}"

    args=(buildx imagetools create)
    [[ "$dry_run" == true ]] && args+=(--dry-run)
    for tag in "${tag_list[@]}"; do
        args+=(--tag "$tag")
    done
    for digest in "${digests[@]}"; do
        args+=("${IMAGE}@${digest}")
    done

    printf '%s -> %s\n' "${targets[$i]}" "${tag_list[*]}"
    "$docker_bin" "${args[@]}"

    if [[ "$dry_run" != true ]]; then
        published="$("$docker_bin" buildx imagetools inspect --raw "${tag_list[0]}" |
            jq -r '[.manifests[]?.platform | select(.os != "unknown") | "\(.os)/\(.architecture)"] | sort | join(" ")')"
        [[ "$published" == "$expected" ]] || die "${tag_list[0]}: platforms '${published}', expected '${expected}'."
    fi

    summary+="| \`${targets[$i]}\` | $(printf "\`%s\` " "${tag_list[@]}")| $(printf "\`%s\` " "${digests[@]}")|"$'\n'
done

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        printf '%s\n' "$summary"
        printf "Version: \`%s\`, rolling tags: \`%s\`, platforms: \`%s\`.\n" "${version:-none}" "$rolling" "${platforms[*]}"
    } >>"$GITHUB_STEP_SUMMARY"
fi
