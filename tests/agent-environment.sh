#!/usr/bin/env bash
# Behavioral evaluation of the portable agent helper: success, precondition failure and cleanup after HTTP failure.
set -euo pipefail

image="${1:-ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/skills/yii2-docker-environment/scripts/validate.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/yii2-docker-eval.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/tmp" "$work/bin"

TMPDIR="$work/tmp" bash "$helper" "$image" >"$work/success.log" 2>&1
cat "$work/success.log"
[[ -z "$(ls -A "$work/tmp")" ]]
container="$(awk '/^Container / {print $2}' "$work/success.log")"
[[ -n "$container" ]]
if docker inspect "$container" >/dev/null 2>&1; then
    echo "Helper left its container: $container" >&2
    exit 1
fi
printf 'PASS: success removes its own container and fixture\n'

if TMPDIR="$work/tmp" bash "$helper" "yii2-docker-check-missing:${work##*/}" >"$work/missing.log" 2>&1; then
    echo 'Expected a missing-image failure.' >&2
    exit 1
fi
[[ -z "$(ls -A "$work/tmp")" ]]
printf 'PASS: missing local image fails before resource allocation\n'

# Let readiness succeed, then fail the application HTTP probe to exercise the helper EXIT trap.
real_curl="$(command -v curl)"
export REAL_CURL="$real_curl"
cat >"$work/bin/curl" <<'CURL'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == http://127.0.0.1:*/ ]]; then exit 7; fi
done
exec "$REAL_CURL" "$@"
CURL
chmod +x "$work/bin/curl"
if PATH="$work/bin:$PATH" TMPDIR="$work/tmp" bash "$helper" "$image" >"$work/failure.log" 2>&1; then
    echo 'Expected an application HTTP failure.' >&2
    exit 1
fi
[[ -z "$(ls -A "$work/tmp")" ]]
container="$(awk '/^Container / {print $2}' "$work/failure.log")"
[[ -n "$container" ]]
if docker inspect "$container" >/dev/null 2>&1; then
    echo "Helper left its container: $container" >&2
    exit 1
fi
printf 'PASS: failed HTTP assertion removes its own container and fixture\n'
