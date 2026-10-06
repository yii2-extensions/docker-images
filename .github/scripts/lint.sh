#!/usr/bin/env bash
# Runs the Docker-specific linters through pinned container images.
#
# Usage: .github/scripts/lint.sh <hadolint|shellcheck>
#
# Run it from the repository root. Set DOCKER to use another Docker CLI binary or wrapper.
set -euo pipefail

readonly HADOLINT_IMAGE="hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d"
readonly SHELLCHECK_IMAGE="koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d"
readonly SHELL_DIRS=(src/script tests)

docker_bin="${DOCKER:-docker}"

die() {
    printf '::error::%s\n' "$1" >&2
    exit 1
}

# Lists Dockerfiles outside hidden directories.
dockerfiles() {
    find . -path './.*' -prune -o -type f \
        \( -name Dockerfile -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) -print | sort
}

# Lists shell scripts by extension or by shell shebang.
shell_scripts() {
    local dir file
    for dir in "${SHELL_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' file; do
            case "$file" in
                *.sh | *.bash | *.bats) printf '%s\n' "$file" ;;
                *) head -n 1 -- "$file" | grep -qE '^#!.*[/ ](ba|da|k)?sh([[:space:]]|$)|^#!.*[/ ]bats' &&
                    printf '%s\n' "$file" ;;
            esac
        done < <(find "$dir" -type f -print0)
    done | sort
}

run_hadolint() {
    local -a files
    mapfile -t files < <(dockerfiles)
    [[ ${#files[@]} -gt 0 ]] || die "No Dockerfile found."
    printf 'hadolint: %s\n' "${files[@]}"
    "$docker_bin" run --rm --network none -v "$PWD:/repo:ro" -w /repo "$HADOLINT_IMAGE" \
        hadolint --config .github/linters/.hadolint.yaml "${files[@]}"
}

run_shellcheck() {
    local -a files
    mapfile -t files < <(shell_scripts)
    [[ ${#files[@]} -gt 0 ]] || die "No shell script found under: ${SHELL_DIRS[*]}."
    printf 'shellcheck: %s\n' "${files[@]}"
    "$docker_bin" run --rm --network none -v "$PWD:/mnt:ro" -w /mnt "$SHELLCHECK_IMAGE" \
        --rcfile .github/linters/.shellcheckrc "${files[@]}"
}

case "${1:-}" in
    hadolint) run_hadolint ;;
    shellcheck) run_shellcheck ;;
    *) die "Usage: $0 <hadolint|shellcheck>" ;;
esac
