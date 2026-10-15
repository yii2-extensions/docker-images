#!/usr/bin/env bash
# Validate a pre-pulled stable image without mounting an application or changing shared Docker resources.
set -euo pipefail

image="${1:-ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0}"
[[ $# -le 1 ]] || {
    echo "Usage: bash validate.sh [local-image]" >&2
    exit 2
}
for command in docker curl python3 mktemp; do
    command -v "$command" >/dev/null || {
        echo "Missing command: $command" >&2
        exit 1
    }
done
[[ "$(id -u)" -ne 0 ]] || {
    echo 'Run as a non-root host user.' >&2
    exit 1
}
docker info >/dev/null
endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
[[ "$endpoint" == unix://* ]] || {
    echo 'Use a local Unix-socket Docker daemon for the fixture bind mount.' >&2
    exit 1
}
docker image inspect "$image" >/dev/null || {
    echo "Pull the verified image first: docker pull $image" >&2
    exit 1
}
variant="$(docker image inspect --format '{{index .Config.Labels "build.type"}}' "$image")"
[[ "$variant" == prod || "$variant" == dev || "$variant" == full ]] || {
    echo 'Expected an image with a build.type label.' >&2
    exit 1
}
docker image inspect --format 'Image {{.Id}} Platform {{.Os}}/{{.Architecture}} User {{.Config.User}}' "$image"

work="$(mktemp -d "${TMPDIR:-/tmp}/yii2-docker-check.XXXXXXXX")"
token="${work##*/}"
container=''
cleanup() {
    local result=$?
    trap - EXIT
    if [[ -s "$work/cid" ]]; then
        container="$(cat "$work/cid")"
        if [[ "$(docker inspect --format '{{index .Config.Labels "yii2-docker-check"}}' "$container" 2>/dev/null)" == "$token" ]]; then
            if [[ $result -ne 0 ]]; then docker logs --tail 80 "$container" >&2 || true; fi
            docker rm -f "$container" >/dev/null || result=1
        else
            echo "Could not confirm ownership of container $container; inspect it manually." >&2
            result=1
        fi
    fi
    rm -rf -- "$work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$work/app/web"
cat >"$work/app/web/index.php" <<'PHP'
<?php

declare(strict_types=1);

header('Content-Type: application/json');
echo json_encode([
    'fixture' => 'ok',
    'https' => ($_SERVER['HTTPS'] ?? '') === 'on',
    'memory_limit' => ini_get('memory_limit'),
    'exec_available' => function_exists('exec'),
    'runtime_write' => file_put_contents(__DIR__ . '/../runtime/probe', 'ok') === 2,
], JSON_THROW_ON_ERROR);
PHP

docker run -d --pull never --cidfile "$work/cid" --label "yii2-docker-check=$token" \
    --user "$(id -u):$(id -g)" --memory 512m --cpus 1 --pids-limit 128 \
    -p 127.0.0.1::80 -p 127.0.0.1::443 \
    --mount "type=bind,src=$work/app,dst=/var/www/app" \
    -e SKIP_COMPOSER_INSTALL=true -e SKIP_DB_WAIT=true -e YII_RUN_MIGRATIONS=false \
    -e YII_ENV=test -e XDEBUG_MODE=off -e PHP_MEMORY_LIMIT=192M \
    "$image" >/dev/null
container="$(cat "$work/cid")"
http="http://$(docker port "$container" 80/tcp)"
https="https://$(docker port "$container" 443/tcp)"
printf 'Container %s\nHTTP %s\nHTTPS %s\n' "$container" "$http" "$https"
ready=false
for ((attempt = 0; attempt < 40; attempt++)); do
    if curl --noproxy '*' --silent --fail --max-time 2 "$http/health" >"$work/health.json"; then
        ready=true
        break
    fi
    [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]] || break
    sleep 1
done
[[ "$ready" == true ]] || {
    echo 'The stack did not become ready.' >&2
    exit 1
}
curl --noproxy '*' --silent --show-error --fail --max-time 5 "$http/" >"$work/http.json"
curl --noproxy '*' --silent --show-error --fail --insecure --max-time 5 "$https/" >"$work/https.json"
python3 - "$work" <<'PY'
import json
from pathlib import Path
import sys
work = Path(sys.argv[1])
health = json.loads((work / 'health.json').read_text())
if not isinstance(health, dict) or health.get('status') != 'healthy':
    raise SystemExit(f'Invalid health response: {health!r}')
for protocol in ('http', 'https'):
    result = json.loads((work / f'{protocol}.json').read_text())
    expected = {
        'fixture': 'ok', 'https': protocol == 'https', 'memory_limit': '192M',
        'exec_available': False, 'runtime_write': True,
    }
    if result != expected:
        raise SystemExit(f'Invalid {protocol} fixture response: expected {expected!r}, got {result!r}')
print('PASS: health, application HTTP/HTTPS, FPM settings, disabled shell functions and runtime write')
PY
[[ "$(curl --noproxy '*' --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "$http/__health")" == 403 ]]
docker exec "$container" healthcheck
docker exec "$container" apache2ctl configtest
docker exec "$container" php -r 'exit(extension_loaded("pdo") && extension_loaded("intl") ? 0 : 1);'
if [[ "$variant" == prod ]]; then
    docker exec "$container" sh -c '! command -v node'
else
    docker exec "$container" node --version
    docker exec "$container" npm --version
    docker exec "$container" php -r 'exit(extension_loaded("xdebug") ? 0 : 1);'
fi
if [[ "$variant" == full ]]; then
    docker exec "$container" php -r 'exit(extension_loaded("oci8") && extension_loaded("pdo_oci") && extension_loaded("sqlsrv") && extension_loaded("pdo_sqlsrv") ? 0 : 1);'
fi
[[ "$(docker exec "$container" id -u)" == "$(id -u)" ]]
[[ "$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_uid)' "$work/app/runtime/probe")" == "$(id -u)" ]]
echo 'PASS: internal health, public health restriction, Apache config, CLI tools and host UID ownership'
echo 'Stack fixture passed; run the application checks separately. Cleaning up this container and temporary fixture.'
