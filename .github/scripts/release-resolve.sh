#!/usr/bin/env bash
# Resolves what the release workflow builds and publishes. Requires a clone with all tags.
#
# Usage: .github/scripts/release-resolve.sh
#
# Environment (GitHub context):
#   EVENT_NAME     `push`, `schedule` or `workflow_dispatch`.
#   REF_TYPE       `tag` for tag pushes.
#   REF_NAME       Tag name for tag pushes (for example `v2.0.0`).
#   INPUT_VERSION  Optional `X.Y.Z` version of a manual run.
#
# Outputs (GITHUB_OUTPUT): `build` (`true`|`false`), `ref`, `version` (empty for rolling-only rebuilds) and `rolling`
# (`true` when the rolling tags and `latest` move, that is, when the built release is the latest one).
set -euo pipefail

readonly STRICT_VERSION='^[0-9]+\.[0-9]+\.[0-9]+$'

die() {
    printf '::error::%s\n' "$1" >&2
    exit 1
}

output() {
    printf '%s=%s\n' "$1" "$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
    fi
}

skip() {
    printf '::notice title=Release skipped::%s\n' "$1"
    output build false
    exit 0
}

latest_tag="$(git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"

version=''
if [[ "${EVENT_NAME:-}" == push && "${REF_TYPE:-}" == tag ]]; then
    version="${REF_NAME:-}"
    version="${version#v}"
elif [[ "${EVENT_NAME:-}" == workflow_dispatch && -n "${INPUT_VERSION:-}" ]]; then
    version="$INPUT_VERSION"
fi

if [[ -n "$version" ]]; then
    [[ "$version" =~ $STRICT_VERSION ]] || die "Invalid version '${version}': expected X.Y.Z."
    tag="v${version}"
    git rev-parse --quiet --verify "refs/tags/${tag}^{commit}" >/dev/null || die "Tag ${tag} does not exist."
    git cat-file -e "refs/tags/${tag}:docker-bake.hcl" 2>/dev/null || die "Tag ${tag} has no docker-bake.hcl."
    rolling=false
    [[ "$tag" == "$latest_tag" ]] && rolling=true
    [[ "$rolling" == true ]] || printf '::notice::%s is not the latest release (%s); only frozen tags move.\n' "$tag" "${latest_tag:-none}"
else
    [[ -n "$latest_tag" ]] || skip "No vX.Y.Z release tag exists yet."
    tag="$latest_tag"
    git cat-file -e "refs/tags/${tag}:docker-bake.hcl" 2>/dev/null ||
        skip "Latest release ${tag} predates docker-bake.hcl; nothing to rebuild."
    rolling=true
fi

output build true
output ref "refs/tags/${tag}"
output version "$version"
output rolling "$rolling"
