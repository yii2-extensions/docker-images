#!/usr/bin/env bash
# Behavioral evaluation of the portable helper, including rejection checks with Python optimization enabled.
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

# Inject failures into host HTTP responses; container-internal requests still use its real curl.
real_curl="$(command -v curl)"
export REAL_CURL="$real_curl"
cat >"$work/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
    if [[ "${PROBE_CASE:-http-failure}" == http-failure && "$arg" == http://127.0.0.1:*/ ]]; then
        exit 7
    fi
    if [[ "${PROBE_CASE:-}" == bad-health && "$arg" == http://127.0.0.1:*/health ]]; then
        "$REAL_CURL" "$@" | python3 -c 'import json,sys; value=json.load(sys.stdin); value["status"]="unhealthy"; print(json.dumps(value))'
        exit 0
    fi
    if [[ "${PROBE_CASE:-}" == bad-fixture && "$arg" == http://127.0.0.1:*/ ]]; then
        "$REAL_CURL" "$@" | python3 -c 'import json,sys; value=json.load(sys.stdin); value["memory_limit"]="64M"; print(json.dumps(value))'
        exit 0
    fi
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

# Python must reject invalid JSON values even when the caller disables assert statements.
for probe in bad-health bad-fixture; do
    if PATH="$work/bin:$PATH" TMPDIR="$work/tmp" PROBE_CASE="$probe" PYTHONOPTIMIZE=1 \
        bash "$helper" "$image" >"$work/$probe.log" 2>&1; then
        echo "Expected $probe to fail with PYTHONOPTIMIZE=1." >&2
        exit 1
    fi
    case "$probe" in
        bad-health) grep -q 'Invalid health response:' "$work/$probe.log" ;;
        bad-fixture) grep -q 'Invalid http fixture response:' "$work/$probe.log" ;;
    esac
    [[ -z "$(ls -A "$work/tmp")" ]]
    container="$(awk '/^Container / {print $2}' "$work/$probe.log")"
    [[ -n "$container" ]]
    if docker inspect "$container" >/dev/null 2>&1; then
        echo "Helper left its container: $container" >&2
        exit 1
    fi
    printf 'PASS: %s rejected with PYTHONOPTIMIZE=1; own container and fixture removed\n' "$probe"
done
