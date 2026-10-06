#!/bin/bash
# Checks pass literal snippets to `bash -c` and `php -r` with positional arguments on purpose.
# shellcheck disable=SC2016
set -euo pipefail

#==============================================================================
# Image smoke tests
#
# Runs as root inside an image, at build time or against a built image:
#   RUN --mount=type=bind,source=tests,target=/opt/tests,readonly bash /opt/tests/smoke.sh
#   docker run --rm -v "$PWD/tests:/opt/tests:ro" --entrypoint bash IMAGE /opt/tests/smoke.sh
#
# Reads BUILD_TYPE (prod, dev, full) and optional PHP_VERSION (for example 8.5).
# Starts the stack through the entrypoint in the background, stops it on exit
# and removes every file it created, so a build-time run leaves no trace.
#==============================================================================

readonly FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixture"
readonly APP_DIR=/var/www/app
readonly WORK_DIR=/tmp/yii2-smoke
readonly STACK_LOG="${WORK_DIR}/stack.log"
readonly UA="Mozilla/5.0 (smoke)"
readonly SNAPSHOT_PATHS=(/var/www /run /etc/apache2 /var/lib/php /var/cache/apache2 /var/log)
readonly BASE_ENV=(SSL_DIR="${WORK_DIR}/ssl" COMPOSER_DISABLE_NETWORK=1)

PASS=0
FAIL=0
SKIP=0
STACK_PID=""
STOP_SECONDS=0
ENTRY_OUT=""
ENTRY_RC=0
APP_COMPOSER_JSON=""

pass() {
    PASS=$((PASS + 1))
    echo "PASS: $*"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL: $*"
}

skip() {
    SKIP=$((SKIP + 1))
    echo "SKIP: $*"
}

# Usage: check <description> <command...>
check() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

snapshot() {
    find "${SNAPSHOT_PATHS[@]}" -xdev 2>/dev/null | sort
}

cleanup() {
    stop_stack || true
    snapshot >"${WORK_DIR}/after.list"
    comm -13 "${WORK_DIR}/before.list" "${WORK_DIR}/after.list" | sort -r | while IFS= read -r path; do
        rm -rf -- "$path"
    done
    rm -rf -- "$WORK_DIR"
}

reset_app() {
    find "$APP_DIR" -mindepth 1 -delete
    cp -r "${FIXTURE_DIR}/." "$APP_DIR/"
    chmod +x "${APP_DIR}/yii"
    printf 'SECRET=smoke\n' >"${APP_DIR}/web/.env"
    printf '{}\n' >"${APP_DIR}/web/composer.json"
    # Published assets may contain directories named like application source directories (jQuery UI ui/widgets)
    mkdir -p "${APP_DIR}/web/assets/smoke/widgets" "${APP_DIR}/web/assets/smoke/vendor"
    printf 'ok\n' >"${APP_DIR}/web/assets/smoke/widgets/menu.js"
    printf 'ok\n' >"${APP_DIR}/web/assets/smoke/vendor/lib.js"
    if [[ -n "$APP_COMPOSER_JSON" ]]; then
        cp "$APP_COMPOSER_JSON" "${APP_DIR}/composer.json"
    fi
}

port_open() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# Usage: start_stack [VAR=value...]
start_stack() {
    : >"$STACK_LOG"
    env "${BASE_ENV[@]}" "$@" /usr/local/bin/entrypoint >>"$STACK_LOG" 2>&1 &
    STACK_PID=$!

    local attempt
    for ((attempt = 0; attempt < 120; attempt++)); do
        if healthcheck >/dev/null 2>&1; then
            return 0
        fi
        if ! kill -0 "$STACK_PID" 2>/dev/null; then
            return 1
        fi
        sleep 0.25
    done
    return 1
}

# Sends SIGTERM to supervisord and records the shutdown time in STOP_SECONDS.
stop_stack() {
    STOP_SECONDS=0
    if [[ -z "$STACK_PID" ]]; then
        return 0
    fi

    local started=$SECONDS
    kill -TERM "$STACK_PID" 2>/dev/null || true
    while kill -0 "$STACK_PID" 2>/dev/null && ((SECONDS - started < 30)); do
        sleep 0.2
    done
    STOP_SECONDS=$((SECONDS - started))

    local rc=0
    if kill -0 "$STACK_PID" 2>/dev/null; then
        kill -KILL "$STACK_PID" 2>/dev/null || true
        rc=1
    fi
    wait "$STACK_PID" 2>/dev/null || true
    STACK_PID=""

    while port_open 80 && ((SECONDS - started < 30)); do
        sleep 0.2
    done
    return $rc
}

# Usage: run_entrypoint [VAR=value...] -- command...
run_entrypoint() {
    local -a vars=()
    while [[ "$1" != "--" ]]; do
        vars+=("$1")
        shift
    done
    shift
    reset_app
    ENTRY_RC=0
    ENTRY_OUT="$(env "${BASE_ENV[@]}" APACHE_SSL_ENABLED=false "${vars[@]}" /usr/local/bin/entrypoint "$@" 2>&1)" || ENTRY_RC=$?
}

entry_reached() {
    [[ "$ENTRY_RC" -eq 0 && "$ENTRY_OUT" == *SMOKE-REACHED* ]]
}

entry_aborted() {
    [[ "$ENTRY_RC" -ne 0 && "$ENTRY_OUT" != *SMOKE-REACHED* ]]
}

body() {
    curl -s --max-time 5 -A "$UA" "$@"
}

status() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 -A "$UA" "$@"
}

contains() {
    [[ "$1" == *"$2"* ]]
}

health_json_valid() {
    body "$1" >"${WORK_DIR}/health.json"
    php -r '
        $d = json_decode(file_get_contents($argv[1]), true);
        $keys = ["status", "timestamp", "service", "version", "environment", "php_version", "checks"];
        exit(is_array($d) && $d["status"] === "healthy" && array_diff($keys, array_keys($d)) === [] ? 0 : 1);
    ' "${WORK_DIR}/health.json"
}

apache_log_sizes() {
    find /var/log/apache2 -type f -printf '%p %s\n' 2>/dev/null | sort
}

#------------------------------------------------------------------------------
# Preconditions
#------------------------------------------------------------------------------
if [[ "$(id -u)" != "0" ]]; then
    echo "smoke.sh must run as root" >&2
    exit 2
fi

case "${BUILD_TYPE:-}" in
prod | dev | full) ;;
*)
    echo "BUILD_TYPE must be prod, dev or full (got '${BUILD_TYPE:-}')" >&2
    exit 2
    ;;
esac

if [[ -d "$APP_DIR" ]] && [[ -n "$(ls -A "$APP_DIR")" ]]; then
    echo "${APP_DIR} must be empty; smoke.sh installs its own fixture" >&2
    exit 2
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$APP_DIR"
snapshot >"${WORK_DIR}/before.list"
trap cleanup EXIT

echo "Smoke tests: BUILD_TYPE=${BUILD_TYPE} PHP_VERSION=${PHP_VERSION:-unset}"

#------------------------------------------------------------------------------
# Static checks
#------------------------------------------------------------------------------
php_running="$(php -n -r 'echo PHP_VERSION;')"
if [[ -n "${PHP_VERSION:-}" ]]; then
    check "PHP ${php_running} matches PHP_VERSION=${PHP_VERSION}" \
        bash -c '[[ "$1" == "$2" || "$1" == "$2".* ]]' _ "$php_running" "$PHP_VERSION"
else
    skip "PHP version match (PHP_VERSION not set; running ${php_running})"
fi

# Expected extensions: the lists the image was built with (the smoke stage passes PHP_EXTENSIONS_*), otherwise the
# Dockerfile defaults. Installer-only entries (@composer) and version suffixes (xdebug-3.4.5) are not module names.
requested="${PHP_EXTENSIONS_PROD-@composer apcu bcmath gd imagick intl opcache pcntl pdo_mysql pdo_pgsql redis zip}"
if [[ "$BUILD_TYPE" != "prod" ]]; then
    requested+=" ${PHP_EXTENSIONS_DEV-memcached mongodb soap xdebug yaml}"
fi
if [[ "$BUILD_TYPE" == "full" ]]; then
    requested+=" ${PHP_EXTENSIONS_FULL-oci8 pdo_oci pdo_sqlsrv sqlsrv tidy}"
fi
extensions=()
for extension in $requested; do
    [[ "$extension" == @* ]] || extensions+=("${extension%%-*}")
done
loaded="$(php -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"
missing=()
for extension in "${extensions[@]}"; do
    grep -qx "$extension" <<<"$loaded" || grep -qx "zend ${extension}" <<<"$loaded" || missing+=("$extension")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "Extensions loaded (${BUILD_TYPE}): ${extensions[*]}"
else
    fail "Extensions missing (${BUILD_TYPE}): ${missing[*]}"
fi

if [[ "$BUILD_TYPE" == "prod" ]]; then
    check "prod does not load xdebug" bash -c '! php -m | grep -qix xdebug'
fi

startup_output="$(php -r 'echo "ok";' 2>&1)"
check "No PHP CLI startup warnings" test "$startup_output" == "ok"
fpm_test="$(php-fpm -t 2>&1)" && fpm_rc=0 || fpm_rc=$?
check "php-fpm -t" test "$fpm_rc" -eq 0
check "No PHP-FPM startup warnings" bash -c '! grep -qiE "warning|deprecated" <<<"$1"' _ "$fpm_test"
check "apache2ctl configtest (static configuration)" apache2ctl configtest
check "No sudo or gosu in the image" bash -c '! command -v sudo && ! command -v gosu && [[ ! -e /etc/sudoers.d/www-data ]]'
check "healthcheck command installed" test -x /usr/local/bin/healthcheck

check "Compiler toolchain absent" bash -c 'for tool in autoconf c++ cc cpp g++ gcc ld make pkg-config re2c; do
    ! command -v "$tool" || exit 1; done'
check "PHP sources and C headers absent" bash -c '[[ ! -e /usr/src/php && ! -e /usr/src/php.tar.xz && ! -e /usr/include/stdio.h ]]'
check "install-extensions installed with a recorded PHP source" bash -c '[[ -x /usr/local/bin/install-extensions ]] &&
    grep -qx "PHP_VERSION=$(php -n -r "echo PHP_VERSION;")" /usr/local/lib/yii2-docker/php-source.env &&
    grep -Eqx "PHP_SHA256=[0-9a-f]{64}" /usr/local/lib/yii2-docker/php-source.env'

check "Ghostscript, its fonts and poppler-data absent" bash -c '! command -v gs &&
    ! dpkg-query -W -f="\${db:Status-Abbrev}\n" ghostscript poppler-data fonts-urw-base35 2>/dev/null | grep -q "^ii"'
if grep -qx imagick <<<"$loaded"; then
    check "Imagick writes and reads PNG, JPEG, WebP and GIF" test "$(php -r '
        foreach (["png", "jpeg", "webp", "gif"] as $format) {
            $image = new Imagick();
            $image->newImage(4, 3, new ImagickPixel("red"));
            $image->setImageFormat($format);
            $copy = new Imagick();
            $copy->readImageBlob($image->getImageBlob());
            if ($copy->getImageWidth() !== 4 || $copy->getImageHeight() !== 3) {
                exit(1);
            }
        }
        echo "ok";' 2>&1)" == "ok"
else
    skip "Imagick raster formats (imagick not built for PHP ${php_running})"
fi

if [[ "$BUILD_TYPE" == "prod" ]]; then
    check "prod has no phpdbg" bash -c '! command -v phpdbg'
    check "prod has no node or npm" bash -c '! command -v node && ! command -v npm && ! command -v npx'
else
    check "node, npm and npx run" bash -c 'node --version && npm --version && npx --version'
fi

#------------------------------------------------------------------------------
# Scenario A: defaults (HTTP + HTTPS), FPM status enabled
#------------------------------------------------------------------------------
reset_app
log_sizes_before="$(apache_log_sizes)"
if start_stack ENABLE_FPM_STATUS=true; then
    pass "Stack boots and healthcheck passes"
else
    fail "Stack boots and healthcheck passes"
    tail -n 40 "$STACK_LOG"
fi

check "Banner reports PHP ${php_running}" grep -q "PHP:.* ${php_running}" "$STACK_LOG"
check "apache2ctl configtest (runtime defines)" apache2ctl configtest
check "Front controller over HTTP" contains "$(body http://127.0.0.1/site/index)" '"fixture":"ok"'
check "Front controller over HTTPS with HTTP/2" \
    test "$(curl -sk --http2 -o /dev/null -w '%{http_version}' -A "$UA" https://127.0.0.1/site/index)" == "2"
check "HTTPS response from the application" contains "$(body -k https://127.0.0.1/site/index)" '"https":true'

for method in PUT PATCH DELETE; do
    check "${method} reaches the application" contains "$(body -X "$method" http://127.0.0.1/api/items/1)" "\"method\":\"${method}\""
done

check "Googlebot User-Agent gets 200" \
    test "$(curl -s -o /dev/null -w '%{http_code}' -A 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' http://127.0.0.1/)" == "200"
check "Default curl User-Agent gets 200" test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/)" == "200"
check "/.env is denied" test "$(status http://127.0.0.1/.env)" == "403"
check "/composer.json is denied" test "$(status http://127.0.0.1/composer.json)" == "403"
check "Published assets under widgets/ and vendor/ are served" bash -c '[[ "$1" == 200 && "$2" == 200 ]]' _ \
    "$(status http://127.0.0.1/assets/smoke/widgets/menu.js)" "$(status http://127.0.0.1/assets/smoke/vendor/lib.js)"

check "Public health endpoint returns the JSON at /health" health_json_valid http://127.0.0.1/health
check "Public health endpoint answers /health/" health_json_valid http://127.0.0.1/health/
check "Application directory has no health directory" test ! -e "${APP_DIR}/web/health"

external_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -n "$external_ip" ]]; then
    check "Internal health endpoint is loopback only" test "$(status "http://${external_ip}/__health")" == "403"
    check "FPM status is loopback only" test "$(status "http://${external_ip}/fpm-status")" == "403"
else
    skip "Loopback-only checks (no non-loopback address)"
fi

check "FPM ping answers pong (ENABLE_FPM_STATUS=true)" test "$(body http://127.0.0.1/fpm-ping)" == "pong"
check "FPM status page (ENABLE_FPM_STATUS=true)" contains "$(body http://127.0.0.1/fpm-status)" "pool:"

if [[ "$BUILD_TYPE" == "prod" ]]; then
    check "Composer skipped by default in prod" test ! -e "${APP_DIR}/vendor"
else
    check "Composer install ran at startup" test -f "${APP_DIR}/vendor/autoload.php"
    check "Composer ran as www-data" test "$(stat -c %U "${APP_DIR}/vendor/autoload.php" 2>/dev/null)" == "www-data"
fi

body http://127.0.0.1/smoke-access-marker >/dev/null
healthcheck >/dev/null 2>&1 || true
sleep 1
check "Access log goes to stdout" grep -q '"url":"/smoke-access-marker"' "$STACK_LOG"
# Served health requests stay out of the log; denied (403) probes from non-loopback addresses are logged on purpose
if grep -E '"url":"/(__)?health/?"' "$STACK_LOG" | grep -q '"status":200'; then
    fail "Health requests are not logged"
    grep -E '"url":"/(__)?health/?"' "$STACK_LOG" | head -n 3
else
    pass "Health requests are not logged"
fi
check "No file grows under /var/log/apache2" test "$(apache_log_sizes)" == "$log_sizes_before"
check "No PHP startup warnings in the stack log" bash -c '! grep -qiE "PHP (Warning|Deprecated)|JIT is incompatible" "$1"' _ "$STACK_LOG"

supervisorctl stop php-fpm >/dev/null 2>&1 || true
check "healthcheck fails when PHP-FPM is down" bash -c '! healthcheck'
supervisorctl start php-fpm >/dev/null 2>&1 || true
check "healthcheck recovers when PHP-FPM is back" healthcheck

if stop_stack && [[ "$STOP_SECONDS" -le 8 ]]; then
    pass "Clean shutdown on SIGTERM (${STOP_SECONDS}s)"
else
    fail "Clean shutdown on SIGTERM (${STOP_SECONDS}s)"
fi

#------------------------------------------------------------------------------
# Scenario B: HTTP only, public health endpoint disabled, FPM status disabled
#------------------------------------------------------------------------------
reset_app
if start_stack APACHE_SSL_ENABLED=false ENABLE_HEALTH_ENDPOINT=false SKIP_COMPOSER_INSTALL=true; then
    pass "HTTP-only stack boots and healthcheck passes with ENABLE_HEALTH_ENDPOINT=false"
else
    fail "HTTP-only stack boots and healthcheck passes with ENABLE_HEALTH_ENDPOINT=false"
fi
check "HTTP-only serves the front controller" contains "$(body http://127.0.0.1/)" '"fixture":"ok"'
check "HTTP-only does not listen on 443" bash -c '! (exec 3<>/dev/tcp/127.0.0.1/443) 2>/dev/null'
check "Disabled public health endpoint falls through to the application" contains "$(body http://127.0.0.1/health)" '"fixture":"ok"'
check "FPM ping is not exposed without ENABLE_FPM_STATUS" contains "$(body http://127.0.0.1/fpm-ping)" '"fixture":"ok"'
stop_stack || fail "HTTP-only stack shutdown"

#------------------------------------------------------------------------------
# Scenario C: HTTP to HTTPS redirect
#------------------------------------------------------------------------------
reset_app
if start_stack APACHE_SSL_REDIRECT=true SKIP_COMPOSER_INSTALL=true; then
    pass "Redirect mode boots and healthcheck passes"
else
    fail "Redirect mode boots and healthcheck passes"
fi
check "Redirect for localhost goes to port 8443" \
    test "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -A "$UA" http://localhost/site?a=1)" == "301 https://localhost:8443/site?a=1"
check "Redirect for other hosts goes to 443" \
    test "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -A "$UA" -H 'Host: example.com' http://127.0.0.1/site)" == "301 https://example.com/site"
check "HTTPS serves the application in redirect mode" contains "$(body -k https://127.0.0.1/site)" '"https":true'
stop_stack || fail "Redirect stack shutdown"

#------------------------------------------------------------------------------
# Entrypoint behavior (command mode)
#------------------------------------------------------------------------------
wait_env=(WAIT_FOR_SERVICES=true DB_MYSQL_HOST=127.0.0.1 DB_MYSQL_PORT=1 SERVICE_WAIT_TIMEOUT=1 SKIP_COMPOSER_INSTALL=true)
run_entrypoint "${wait_env[@]}" FAIL_ON_SERVICE_TIMEOUT=false -- echo SMOKE-REACHED
check "FAIL_ON_SERVICE_TIMEOUT=false continues" entry_reached
run_entrypoint "${wait_env[@]}" FAIL_ON_SERVICE_TIMEOUT=true -- echo SMOKE-REACHED
check "FAIL_ON_SERVICE_TIMEOUT=true exits non-zero" entry_aborted

# An unresolvable requirement fails fast because COMPOSER_DISABLE_NETWORK=1
printf '{"require":{"yii2-extensions/smoke-missing-package":"1.0"}}\n' >"${WORK_DIR}/composer-fail.json"
APP_COMPOSER_JSON="${WORK_DIR}/composer-fail.json"
run_entrypoint SKIP_COMPOSER_INSTALL=false FAIL_ON_COMPOSER_ERROR=false -- echo SMOKE-REACHED
check "FAIL_ON_COMPOSER_ERROR=false continues" entry_reached
run_entrypoint SKIP_COMPOSER_INSTALL=false FAIL_ON_COMPOSER_ERROR=true -- echo SMOKE-REACHED
check "FAIL_ON_COMPOSER_ERROR=true exits non-zero" entry_aborted
APP_COMPOSER_JSON=""

migration_env=(YII_RUN_MIGRATIONS=true SKIP_COMPOSER_INSTALL=true)
run_entrypoint "${migration_env[@]}" -- echo SMOKE-REACHED
check "Migrations run as www-data" bash -c '[[ "$1" == *"SMOKE-YII uid=33 args=migrate --interactive=0"* ]]' _ "$ENTRY_OUT"
run_entrypoint "${migration_env[@]}" SMOKE_MIGRATION_FAIL=1 FAIL_ON_MIGRATION_ERROR=false -- echo SMOKE-REACHED
check "FAIL_ON_MIGRATION_ERROR=false continues" entry_reached
run_entrypoint "${migration_env[@]}" SMOKE_MIGRATION_FAIL=1 -- echo SMOKE-REACHED
check "FAIL_ON_MIGRATION_ERROR defaults to true and exits non-zero" entry_aborted

run_entrypoint BUILD_TYPE=prod SKIP_COMPOSER_INSTALL=false -- echo SMOKE-REACHED
check "Explicit SKIP_COMPOSER_INSTALL=false runs Composer in prod" bash -c '[[ "$1" -eq 0 && -f "$2" ]]' _ "$ENTRY_RC" "${APP_DIR}/vendor/autoload.php"
run_entrypoint BUILD_TYPE=dev SKIP_COMPOSER_INSTALL=true -- echo SMOKE-REACHED
check "Explicit SKIP_COMPOSER_INSTALL=true skips Composer in dev" bash -c '[[ "$1" -eq 0 && ! -e "$2" ]]' _ "$ENTRY_RC" "${APP_DIR}/vendor"

run_entrypoint APACHE_SSL_ENABLED=true SSL_AUTO_GENERATE=false SSL_DIR="${WORK_DIR}/no-certs" SKIP_COMPOSER_INSTALL=true -- cat /var/run/apache2/runtime.env
check "Missing certificates without auto-generation fall back to HTTP-only" \
    bash -c '[[ "$1" -eq 0 && "$2" != *SSL_ENABLED* && "$2" == *"falling back to HTTP-only"* ]]' _ "$ENTRY_RC" "$ENTRY_OUT"

cp "${WORK_DIR}/ssl/cert.pem" "${WORK_DIR}/chain.pem"
run_entrypoint APACHE_SSL_ENABLED=true SSL_AUTO_GENERATE=false SSL_CHAIN_FILE="${WORK_DIR}/chain.pem" SKIP_COMPOSER_INSTALL=true -- cat /var/run/apache2/runtime.env
check "External certificates enable OCSP stapling and the chain file" \
    bash -c '[[ "$1" == *"-D SSL_ENABLED"* && "$1" == *"-D SSL_CHAIN"* && "$1" == *"-D SSL_STAPLING"* ]]' _ "$ENTRY_OUT"
check "apache2ctl configtest with SSL_CHAIN and SSL_STAPLING" apache2ctl configtest
run_entrypoint APACHE_SSL_ENABLED=true SSL_AUTO_GENERATE=false APACHE_DISABLE_OCSP_STAPLING=true SKIP_COMPOSER_INSTALL=true -- cat /var/run/apache2/runtime.env
check "APACHE_DISABLE_OCSP_STAPLING=true disables stapling" bash -c '[[ "$1" == *"-D SSL_ENABLED"* && "$1" != *SSL_STAPLING* ]]' _ "$ENTRY_OUT"

reset_app
ENTRY_RC=0
ENTRY_OUT="$(env "${BASE_ENV[@]}" SKIP_COMPOSER_INSTALL=true setpriv --reuid=www-data --regid=www-data --clear-groups /usr/local/bin/entrypoint echo SMOKE-REACHED 2>&1)" || ENTRY_RC=$?
check "Non-root start skips system configuration and runs the command" \
    bash -c '[[ "$1" -eq 0 && "$2" == *SMOKE-REACHED* && "$2" == *"skipping system configuration"* ]]' _ "$ENTRY_RC" "$ENTRY_OUT"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo "Summary (${BUILD_TYPE}): ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
