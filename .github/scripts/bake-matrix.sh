#!/usr/bin/env bash
# Derives the PHP build matrix from `docker buildx bake --print`, so docker-bake.hcl stays the single source of truth.
#
# Usage: .github/scripts/bake-matrix.sh [bake-group]
#
# Prints a JSON array of {version, base, slug, experimental} objects and, on GitHub Actions, writes it to the `php`
# step output. A version is experimental when its PHP_BASE_TAG differs from its PHP_VERSION.
set -euo pipefail

docker_bin="${DOCKER:-docker}"
group="${1:-image}"

die() {
    printf '::error::%s\n' "$1" >&2
    exit 1
}

bake_json="$("$docker_bin" buildx bake --print "$group")" || die "bake --print ${group} failed."

php="$(jq -c '
    [.target[] | .args | {version: .PHP_VERSION, base: .PHP_BASE_TAG}]
    | if any(.[]; .version == null or .base == null) then error("target without PHP_VERSION/PHP_BASE_TAG") end
    | unique_by(.version)
    | sort_by(.version | split(".") | map(tonumber))
    | map(. + {slug: (.version | gsub("\\."; "-")), experimental: (.base != .version)})
' <<<"$bake_json")" || die "Cannot derive the PHP matrix from bake group '${group}'."

[[ "$(jq 'length' <<<"$php")" -gt 0 ]] || die "Bake group '${group}' has no targets."

jq -r '.[] | "PHP \(.version) (base \(.base))\(if .experimental then " [experimental]" else "" end)"' <<<"$php" >&2
printf '%s\n' "$php"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'php=%s\n' "$php" >>"$GITHUB_OUTPUT"
fi
