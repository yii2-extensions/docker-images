#!/bin/bash
# Checks pass literal snippets to `bash -c` and `php -r` with positional arguments on purpose.
# shellcheck disable=SC2016
set -euo pipefail

#==============================================================================
# Image smoke tests
#
# Runs as root inside an image, at build time or against a built image:
#   RUN --mount=type=bind,source=tests,target=/opt/tests,readonly bash /opt/tests/smoke.sh
#   docker run --rm --user root -v "$PWD/tests:/opt/tests:ro" --entrypoint bash IMAGE /opt/tests/smoke.sh
#
# Reads BUILD_TYPE (prod, dev, full) and optional PHP_VERSION (for example 8.5).
# Starts the stack in the three privilege modes, one after the other: www-data
# (the image default), an arbitrary UID:GID without passwd entry, and root.
# Build steps keep ports below 1024 privileged, so the non-root modes listen on
# 8080 and 8443 through APACHE_HTTP_PORT and APACHE_HTTPS_PORT; root keeps 80
# and 443. Every run needs its own network namespace; the Dockerfile smoke
# stage runs with RUN --network=none.
# Starts the stack through the entrypoint in the background, stops it on exit
# and removes every file it created, so a build-time run leaves no trace.
# supervisord runs at loglevel info through a wrapper in the suite's PATH (the
# image keeps warn), so the shutdown checks read how every program stopped.
#==============================================================================

readonly FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixture"
readonly APP_DIR=/var/www/app
readonly WORK_DIR=/tmp/yii2-smoke
readonly SHIM_DIR="${WORK_DIR}/bin"
readonly STACK_LOG="${WORK_DIR}/stack.log"
readonly STOP_LOG="${WORK_DIR}/stop.log"
readonly UA="Mozilla/5.0 (smoke)"
readonly SNAPSHOT_PATHS=(/var/www /run /etc/apache2 /tmp /var/log)
readonly BASE_ENV=(COMPOSER_DISABLE_NETWORK=1)
readonly RUN_DIR=/run/yii2
readonly APACHE_ENV_FILE="${RUN_DIR}/apache/runtime.env"
readonly ANY_UID=4242
# A SIGTERM stop must end within the stopwaitsecs of apache2 and php-fpm added up, the time supervisord needs to
# force-kill both. A program that ignores its stop signal shows up earlier, as a SIGKILL in the stop log.
readonly STOP_LIMIT_SECONDS=20

# Current privilege mode (www-data, uid, root) and its ports, set by use_mode
MODE=root
MODE_UID=0
MODE_PREFIX=(env)
HTTP_PORT=80
HTTPS_PORT=443
H=http://127.0.0.1
S=https://127.0.0.1

PASS=0
FAIL=0
SKIP=0
STACK_PID=""
STOP_SECONDS=0
STOP_LEFTOVER=""
ENTRY_OUT=""
ENTRY_RC=0
APP_COMPOSER_JSON=""
COMPLETED=false
LAST_ERROR=""

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
    fresh_runtime || true
    snapshot >"${WORK_DIR}/after.list"
    comm -13 "${WORK_DIR}/before.list" "${WORK_DIR}/after.list" | sort -r | while IFS= read -r path; do
        rm -rf -- "$path"
    done
    rm -rf -- "$WORK_DIR"
}

# EXIT trap: cleans up and always prints the summary; an unexpected exit counts as a failure.
finish() {
    local rc=$?
    cleanup || true
    if [[ "$COMPLETED" != true ]]; then
        fail "smoke.sh aborted with exit status ${rc}${LAST_ERROR:+ after: ${LAST_ERROR}}"
    fi
    echo "Summary (${BUILD_TYPE}): ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
    exit 0
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
    # The application belongs to the mode user, as a COPY --chown or a bind mount of the host user's project would
    if [[ "$MODE" != root ]]; then
        chown -R "${MODE_UID}:${MODE_UID}" "$APP_DIR"
    fi
}

# Usage: use_mode <www-data|uid|root>
use_mode() {
    MODE="$1"
    # The command prefix runs a command as the mode user the way docker run --user would: www-data with its home, an
    # arbitrary UID with HOME=/ and no supplementary groups, root unchanged. It execs, so a background PID is the stack.
    case "$MODE" in
    www-data)
        MODE_UID=33 HTTP_PORT=8080 HTTPS_PORT=8443
        MODE_PREFIX=(setpriv --reuid=33 --regid=33 --init-groups env HOME=/var/www)
        ;;
    uid)
        MODE_UID=$ANY_UID HTTP_PORT=8080 HTTPS_PORT=8443
        MODE_PREFIX=(setpriv --reuid="$ANY_UID" --regid="$ANY_UID" --clear-groups env HOME=/)
        ;;
    root)
        MODE_UID=0 HTTP_PORT=80 HTTPS_PORT=443
        MODE_PREFIX=(env)
        ;;
    esac
    H="http://127.0.0.1:${HTTP_PORT}"
    S="https://127.0.0.1:${HTTPS_PORT}"
    # The healthcheck command reads the port like the Docker HEALTHCHECK does
    export APACHE_HTTP_PORT="$HTTP_PORT" APACHE_HTTPS_PORT="$HTTPS_PORT"
}

# Usage: as_mode <command...>
as_mode() {
    "${MODE_PREFIX[@]}" "$@"
}

# Usage: as_mode_piped <command...>
# Runs a command as the mode user with its output on a pipe that user owns, because PHP-FPM and Apache reopen
# /proc/self/fd/2, which fails on the root-owned standard streams of a build step (docker run hands them to the user).
as_mode_piped() {
    "${MODE_PREFIX[@]}" bash -c 'set -o pipefail; "$@" 2>&1 | cat' _ "$@"
}

as_www_data() {
    setpriv --reuid=33 --regid=33 --init-groups "$@"
}

# Resets the runtime directory to the image state, as in a new container.
fresh_runtime() {
    find "$RUN_DIR" -mindepth 1 -delete
    chown root:root "$RUN_DIR"
    chmod 1777 "$RUN_DIR"
}

# Prints "<name> <uid>" for every stack process (supervisord, apache2, php-fpm), one line per distinct pair.
stack_process_users() {
    local status name uid
    for status in /proc/[0-9]*/status; do
        name="$(sed -n 's/^Name:\t//p' "$status" 2>/dev/null)" || continue
        uid="$(awk '/^Uid:/ { print ($2 == $3 && $3 == $4 && $4 == $5) ? $2 : "mixed" }' "$status" 2>/dev/null)" || continue
        case "$name" in
        supervisord | apache2) echo "${name} ${uid}" ;;
        php-fpm*) echo "php-fpm ${uid}" ;;
        esac
    done | sort -u | paste -sd ' '
}

# Prints "<name>[<pid>]" for every stack process still alive (zombies excluded), space separated.
stack_processes() {
    local status
    for status in /proc/[0-9]*/status; do
        awk -F '\t' -v pid="${status//[^0-9]/}" '
            $1 == "Name:" { name = $2 }
            $1 == "State:" { state = substr($2, 1, 1) }
            END { if (state != "Z" && name ~ /^(supervisord|apache2|php-fpm)/) print name "[" pid "]" }
        ' "$status" 2>/dev/null || true
    done | paste -sd ' '
}

# Prints the supervised programs that are up, one per line: RUNNING, or STARTING while inside their startsecs.
running_programs() {
    supervisorctl status 2>/dev/null | awk '$2 == "RUNNING" || $2 == "STARTING" { sub(/^.*:/, "", $1); print $1 }' || true
}

port_open() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# Usage: start_stack [VAR=value...]
start_stack() {
    # The log belongs to the mode user, who reopens it through /dev/stdout and /proc/self/fd/2
    : >"$STACK_LOG"
    chown "$MODE_UID" "$STACK_LOG"
    fresh_runtime
    "${MODE_PREFIX[@]}" env "${BASE_ENV[@]}" PATH="${SHIM_DIR}:${PATH}" APACHE_HTTP_PORT="$HTTP_PORT" \
        APACHE_HTTPS_PORT="$HTTPS_PORT" "$@" /usr/local/bin/entrypoint >>"$STACK_LOG" 2>&1 &
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

# Prints the evidence for a stack that did not boot or did not survive: how the entrypoint ended, the supervised
# programs, the open ports, the stack log and the configuration tests.
stack_diagnostics() {
    local rc=0
    echo "---- stack diagnostics ($(uname -m), PHP ${php_running:-unknown}) ----"
    if [[ -n "$STACK_PID" ]] && ! kill -0 "$STACK_PID" 2>/dev/null; then
        wait "$STACK_PID" 2>/dev/null || rc=$?
        STACK_PID=""
        echo "Entrypoint exited with status ${rc}"
    else
        echo "Entrypoint still running; healthcheck output: $(healthcheck 2>&1 | head -c 300)"
        supervisorctl status 2>&1 | head -n 10 || true
    fi
    echo "Mode ${MODE}; stack processes: $(stack_process_users)"
    echo "Port ${HTTP_PORT}: $(port_open "$HTTP_PORT" && echo open || echo closed); port ${HTTPS_PORT}: $(port_open "$HTTPS_PORT" && echo open || echo closed)"
    echo "---- last 80 lines of the stack log ----"
    tail -n 80 "$STACK_LOG" || true
    report_command as_mode_piped php-fpm -t
    report_command as_mode_piped apache2ctl configtest
    echo "---- end of stack diagnostics ----"
}

# Usage: report_command <command...>
# Prints the exit status and the last lines of the output of a diagnostic command.
report_command() {
    local rc=0 output
    output="$("$@" 2>&1)" || rc=$?
    echo "---- $*: exit status ${rc} ----"
    if [[ -n "$output" ]]; then
        tail -n 10 <<<"$output"
    fi
}

# Usage: boot_stack <description> [VAR=value...]
# Starts the stack and records the result; on failure prints the diagnostics and skips the checks that need it.
boot_stack() {
    local description="$1"
    shift
    # A listener left by another stack sharing this network namespace would answer the healthcheck instead
    if port_open "$HTTP_PORT" || port_open "$HTTPS_PORT"; then
        fail "${description}: port ${HTTP_PORT} or ${HTTPS_PORT} is already in use before the start (shared network namespace?)"
        skip "Checks that need this stack (it did not boot)"
        return 1
    fi
    if start_stack "$@"; then
        pass "$description"
        return 0
    fi
    fail "$description"
    stack_diagnostics
    stop_stack || true
    skip "Checks that need this stack (it did not boot)"
    return 1
}

# Usage: stack_survived <scenario>
# Fails, with diagnostics, when the stack exited while the scenario ran.
stack_survived() {
    if kill -0 "$STACK_PID" 2>/dev/null; then
        pass "Stack still running after ${1}"
        return 0
    fi
    fail "Stack still running after ${1}"
    stack_diagnostics
    return 1
}

# Sends SIGTERM to supervisord and waits until it exited, no stack process is left and the HTTP port is closed.
# Records the time in STOP_SECONDS, what is still running in STOP_LEFTOVER and the stack log lines written since the
# signal in STOP_LOG. Returns 1 when supervisord itself did not exit and had to be killed.
stop_stack() {
    STOP_SECONDS=0
    STOP_LEFTOVER=""
    if [[ -z "$STACK_PID" ]]; then
        return 0
    fi

    local started=$SECONDS logged rc=0
    logged="$(wc -l <"$STACK_LOG")"
    kill -TERM "$STACK_PID" 2>/dev/null || true
    while kill -0 "$STACK_PID" 2>/dev/null && ((SECONDS - started < 30)); do
        sleep 0.2
    done
    if kill -0 "$STACK_PID" 2>/dev/null; then
        kill -KILL "$STACK_PID" 2>/dev/null || true
        rc=1
    fi
    wait "$STACK_PID" 2>/dev/null || true
    STACK_PID=""

    while { [[ -n "$(stack_processes)" ]] || port_open "$HTTP_PORT"; } && ((SECONDS - started < 30)); do
        sleep 0.2
    done
    STOP_SECONDS=$((SECONDS - started))
    STOP_LEFTOVER="$(stack_processes)"
    tail -n +"$((logged + 1))" "$STACK_LOG" >"$STOP_LOG"
    return $rc
}

# Usage: shutdown_problems <program...>
# Prints what made the last stop not graceful, from the supervisord lines logged since the SIGTERM: every program that
# was up must have stopped on its own or on its stop signal (exit status 0, terminated by SIGTERM or SIGQUIT),
# none may have needed the SIGKILL supervisord sends after stopwaitsecs, nothing may be left running and the stop must
# end within STOP_LIMIT_SECONDS. Prints nothing for a graceful stop.
shutdown_problems() {
    local program line
    grep -q 'received SIGTERM indicating exit request' "$STOP_LOG" || echo "supervisord did not log the SIGTERM"
    [[ $# -gt 0 ]] || echo "no supervised program was up before the stop"
    for program in "$@"; do
        line="$(grep -F "stopped: ${program} (" "$STOP_LOG" | tail -n 1)" || true
        if [[ -z "$line" ]]; then
            echo "${program}: no 'stopped: ${program}' line"
        elif ! grep -qE '\((exit status 0|terminated by SIG(TERM|QUIT))\)$' <<<"$line"; then
            echo "stopped: ${line#*stopped: }"
        fi
    done
    grep -F 'with SIGKILL' "$STOP_LOG" | sed 's/^.* killing /forced kill: /' || true
    [[ -z "$STOP_LEFTOVER" ]] || echo "still running: ${STOP_LEFTOVER}"
    ((STOP_SECONDS <= STOP_LIMIT_SECONDS)) || echo "took ${STOP_SECONDS}s (limit ${STOP_LIMIT_SECONDS}s)"
}

# Usage: run_entrypoint [VAR=value...] -- command...
# Resets the application, then runs the entrypoint in command mode as the mode user.
run_entrypoint() {
    reset_app
    run_entrypoint_keep "$@"
}

# Usage: run_entrypoint_keep [VAR=value...] -- command...
# Same as run_entrypoint, on the application as it is.
run_entrypoint_keep() {
    local -a vars=()
    while [[ "$1" != "--" ]]; do
        vars+=("$1")
        shift
    done
    shift
    fresh_runtime
    ENTRY_RC=0
    ENTRY_OUT="$(as_mode env "${BASE_ENV[@]}" APACHE_SSL_ENABLED=false "${vars[@]}" /usr/local/bin/entrypoint "$@" 2>&1)" ||
        ENTRY_RC=$?
}

entry_reached() {
    [[ "$ENTRY_RC" -eq 0 && "$ENTRY_OUT" == *SMOKE-REACHED* ]]
}

entry_aborted() {
    [[ "$ENTRY_RC" -ne 0 && "$ENTRY_OUT" != *SMOKE-REACHED* ]]
}

# HTTP helpers never fail: a connection error yields an empty body or the status 000, and the check decides.
body() {
    curl -s --max-time 5 -A "$UA" "$@" || true
}

status() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 -A "$UA" "$@" || true
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
mkdir -p "$WORK_DIR" "$APP_DIR" "$SHIM_DIR"
# supervisord logs a stop with exit status 0 at INFO; every mode user runs the wrapper
printf '#!/bin/sh\nexec %s "$@" --loglevel=info\n' "$(command -v supervisord)" >"${SHIM_DIR}/supervisord"
chmod 0755 "$WORK_DIR" "$SHIM_DIR" "${SHIM_DIR}/supervisord"
snapshot >"${WORK_DIR}/before.list"
trap finish EXIT
trap 'LAST_ERROR="line ${LINENO}: ${BASH_COMMAND}"' ERR

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
# Static checks per user: the configuration tests pass without warnings for every user that can start the stack
#------------------------------------------------------------------------------
for mode in www-data uid; do
    use_mode "$mode"
    fpm_test="$(as_mode bash -c 'php-fpm -t 2>&1 | cat; exit "${PIPESTATUS[0]}"')" && fpm_rc=0 || fpm_rc=$?
    check "php-fpm -t as ${mode} without warnings" bash -c '[[ "$1" -eq 0 ]] && ! grep -qiE "warning|deprecated|error" <<<"$2"' \
        _ "$fpm_rc" "$fpm_test"
    check "apache2ctl configtest as ${mode}" as_mode_piped apache2ctl configtest
done
check "Image runtime directory is world-writable with the sticky bit and owned by root" \
    test "$(stat -c '%a %U' "$RUN_DIR")" == "1777 root"
check "Nothing under /etc/apache2 belongs to www-data or is writable by it" \
    bash -c '[[ -z "$(find /etc/apache2 \( -user www-data -o -perm -o+w \) ! -type l -print -quit)" ]]'

#------------------------------------------------------------------------------
# Scenario A, per privilege mode: defaults (HTTP + HTTPS), FPM status enabled
#------------------------------------------------------------------------------
# Usage: www_data_can_tamper <dir>
# Succeeds when www-data can add a file to the directory, move it, or change or delete its runtime.env.
www_data_can_tamper() {
    as_www_data bash -c '(: >"$1/smoke-new") 2>/dev/null || mv "$1" "$1.moved" 2>/dev/null ||
        { [[ -e "$1/runtime.env" ]] && { (: >>"$1/runtime.env") 2>/dev/null || rm "$1/runtime.env" 2>/dev/null; }; }' _ "$1"
}

# Succeeds when www-data can tamper with none of the runtime directories root uses and root owns runtime.env.
root_runtime_sealed() {
    local dir
    for dir in apache php supervisor ssl; do
        if www_data_can_tamper "${RUN_DIR}/${dir}"; then
            return 1
        fi
    done
    [[ "$(stat -c %U "$APACHE_ENV_FILE")" == root ]]
}

# Usage: scenario_stack <mode>
scenario_stack() {
    use_mode "$1"
    local label="[$1]" owner expected
    case "$1" in
    www-data) owner=www-data expected="apache2 33 php-fpm 33 supervisord 33" ;;
    uid) owner="UNKNOWN" expected="apache2 ${ANY_UID} php-fpm ${ANY_UID} supervisord ${ANY_UID}" ;;
    root) owner=www-data expected="apache2 0 apache2 33 php-fpm 0 php-fpm 33 supervisord 0" ;;
    esac

    reset_app
    if [[ "$1" == root ]]; then
        # A directory that only root may change, and a link to it where the application keeps runtime files
        install -d -m 0755 /etc/yii2-smoke-target
        rm -rf "${APP_DIR}/runtime"
        ln -s /etc/yii2-smoke-target "${APP_DIR}/runtime"
    fi
    log_sizes_before="$(apache_log_sizes)"
    if ! boot_stack "${label} Stack boots on ports ${HTTP_PORT}/${HTTPS_PORT} and healthcheck passes" ENABLE_FPM_STATUS=true; then
        rm -rf /etc/yii2-smoke-target
        return 0
    fi

    check "${label} Stack processes run as expected (${expected})" test "$(stack_process_users)" == "$expected"
    check "${label} Banner reports PHP ${php_running}" grep -q "PHP:.* ${php_running}" "$STACK_LOG"
    check "${label} apache2ctl configtest (runtime defines)" as_mode_piped apache2ctl configtest
    check "${label} Front controller over HTTP" contains "$(body "${H}/site/index")" '"fixture":"ok"'
    check "${label} Default PHP_DISABLE_FUNCTIONS applies to web requests" \
        contains "$(body "${H}/site/index")" '"functions":{"exec":false,"shell_exec":false,"parse_ini_file":true}'
    check "${label} Front controller over HTTPS with HTTP/2" \
        test "$(curl -sk --http2 -o /dev/null -w '%{http_version}' -A "$UA" "${S}/site/index")" == "2"
    check "${label} HTTPS response from the application" contains "$(body -k "${S}/site/index")" '"https":true'

    for method in PUT PATCH DELETE; do
        check "${label} ${method} reaches the application" \
            contains "$(body -X "$method" "${H}/api/items/1")" "\"method\":\"${method}\""
    done

    check "${label} Googlebot User-Agent gets 200" \
        test "$(curl -s -o /dev/null -w '%{http_code}' -A 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' "${H}/")" == "200"
    check "${label} Default curl User-Agent gets 200" test "$(curl -s -o /dev/null -w '%{http_code}' "${H}/")" == "200"
    check "${label} /.env is denied" test "$(status "${H}/.env")" == "403"
    check "${label} /composer.json is denied" test "$(status "${H}/composer.json")" == "403"
    check "${label} Published assets under widgets/ and vendor/ are served" bash -c '[[ "$1" == 200 && "$2" == 200 ]]' _ \
        "$(status "${H}/assets/smoke/widgets/menu.js")" "$(status "${H}/assets/smoke/vendor/lib.js")"

    check "${label} Public health endpoint returns the JSON at /health" health_json_valid "${H}/health"
    check "${label} Public health endpoint answers /health/" health_json_valid "${H}/health/"
    check "${label} Application directory has no health directory" test ! -e "${APP_DIR}/web/health"

    # Any client address other than 127.0.0.1 and ::1 is denied; 127.0.0.2 needs no network interface besides lo
    check "${label} Internal health endpoint is loopback only" test "$(status --interface 127.0.0.2 "${H}/__health")" == "403"
    check "${label} FPM status is loopback only" test "$(status --interface 127.0.0.2 "${H}/fpm-status")" == "403"
    check "${label} FPM ping answers pong (ENABLE_FPM_STATUS=true)" test "$(body "${H}/fpm-ping")" == "pong"
    check "${label} FPM status page (ENABLE_FPM_STATUS=true)" contains "$(body "${H}/fpm-status")" "pool:"

    if [[ "$BUILD_TYPE" == "prod" ]]; then
        check "${label} Composer skipped by default in prod" test ! -e "${APP_DIR}/vendor"
    else
        check "${label} Composer install ran at startup" test -f "${APP_DIR}/vendor/autoload.php"
        check "${label} Composer output belongs to ${owner}" \
            test "$(stat -c %U "${APP_DIR}/vendor/autoload.php" 2>/dev/null)" == "$owner"
    fi

    if [[ "$1" == root ]]; then
        # Security boundary of the root mode, checked as www-data while the stack runs
        check "${label} www-data cannot modify, replace or add root's runtime files" root_runtime_sealed
        check "${label} www-data cannot replace the OpenSSL configuration" as_www_data bash -c '
            ! (: >>/etc/apache2/ssl/openssl.conf) 2>/dev/null && ! (: >/etc/apache2/ssl/new) 2>/dev/null &&
                ! mv /etc/apache2/ssl/openssl.conf /tmp/ 2>/dev/null'
        check "${label} Generated key exists and www-data cannot read it" bash -c '[[ -s "$1" ]] &&
            ! setpriv --reuid=33 --regid=33 --init-groups cat "$1" >/dev/null 2>&1' _ "${RUN_DIR}/ssl/key.pem"
        check "${label} A runtime link in the application does not change a system directory" \
            test "$(stat -c '%U:%G %a' /etc/yii2-smoke-target)" == "root:root 755"
        rm -rf /etc/yii2-smoke-target
    fi

    body "${H}/smoke-access-marker" >/dev/null
    healthcheck >/dev/null 2>&1 || true
    sleep 1
    check "${label} Access log goes to stdout" grep -q '"url":"/smoke-access-marker"' "$STACK_LOG"
    # Served health requests stay out of the log; denied (403) probes from other client addresses are logged on purpose
    if grep -E '"url":"/(__)?health/?"' "$STACK_LOG" | grep -q '"status":200'; then
        fail "${label} Health requests are not logged"
        grep -E '"url":"/(__)?health/?"' "$STACK_LOG" | head -n 3
    else
        pass "${label} Health requests are not logged"
    fi
    check "${label} No file grows under /var/log/apache2" test "$(apache_log_sizes)" == "$log_sizes_before"
    check "${label} No PHP or PHP-FPM startup warnings in the stack log" \
        bash -c '! grep -qiE "PHP (Warning|Deprecated)|JIT is incompatible|\] (WARNING|ERROR|ALERT):" "$1"' _ "$STACK_LOG"

    supervisorctl stop php-fpm >/dev/null 2>&1 || true
    check "${label} healthcheck fails when PHP-FPM is down" bash -c '! healthcheck'
    supervisorctl start php-fpm >/dev/null 2>&1 || true
    check "${label} healthcheck recovers when PHP-FPM is back" healthcheck

    stack_survived "the ${1} scenario" || true
    local -a programs
    local problems=""
    mapfile -t programs < <(running_programs)
    stop_stack || problems="supervisord did not exit within 30s and was killed"$'\n'
    problems+="$(shutdown_problems "${programs[@]}")"
    if [[ -z "${problems//$'\n'/}" ]]; then
        pass "${label} Clean shutdown on SIGTERM (${STOP_SECONDS}s)"
    else
        fail "${label} Clean shutdown on SIGTERM (${STOP_SECONDS}s)"
        grep -v '^$' <<<"$problems" | sed 's/^/    /'
        echo "---- supervisord lines since the SIGTERM (programs up before it: ${programs[*]:-none}) ----"
        grep -E '^[0-9-]{10} [0-9:,]+ [A-Z]{4} ' "$STOP_LOG" | tail -n 20 || true
    fi
}

for mode in www-data uid root; do
    scenario_stack "$mode"
done

#------------------------------------------------------------------------------
# Scenario B: HTTP only, public health endpoint disabled, FPM status disabled, custom disable_functions (www-data)
#------------------------------------------------------------------------------
use_mode www-data
# The unused HTTPS port keeps its privileged default; it must not stop a non-root HTTP-only stack from starting
HTTPS_PORT=443
reset_app
if boot_stack "[www-data] HTTP-only stack boots on ${HTTP_PORT} with APACHE_HTTPS_PORT=${HTTPS_PORT} and ENABLE_HEALTH_ENDPOINT=false" \
    APACHE_SSL_ENABLED=false ENABLE_HEALTH_ENDPOINT=false SKIP_COMPOSER_INSTALL=true PHP_DISABLE_FUNCTIONS=shell_exec; then
    check "HTTP-only serves the front controller" contains "$(body "${H}/")" '"fixture":"ok"'
    check "PHP_DISABLE_FUNCTIONS=shell_exec applies to web requests" \
        contains "$(body "${H}/")" '"functions":{"exec":true,"shell_exec":false,"parse_ini_file":true}'
    check "HTTP-only does not listen on ${HTTPS_PORT}" bash -c '! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null' _ "$HTTPS_PORT"
    check "Disabled public health endpoint falls through to the application" contains "$(body "${H}/health")" '"fixture":"ok"'
    check "FPM ping is not exposed without ENABLE_FPM_STATUS" contains "$(body "${H}/fpm-ping")" '"fixture":"ok"'
    stack_survived "the HTTP-only scenario" || true
    stop_stack || fail "HTTP-only stack shutdown"
fi

#------------------------------------------------------------------------------
# Scenario C: HTTP to HTTPS redirect, default HTTPS port (root) and custom HTTPS port (arbitrary UID)
#------------------------------------------------------------------------------
use_mode root
reset_app
if boot_stack "[root] Redirect mode boots and healthcheck passes" APACHE_SSL_REDIRECT=true SKIP_COMPOSER_INSTALL=true; then
    check "Redirect for localhost goes to port 8443" \
        test "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -A "$UA" http://localhost/site?a=1)" == "301 https://localhost:8443/site?a=1"
    check "Redirect for other hosts goes to 443" \
        test "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -A "$UA" -H 'Host: example.com' "${H}/site")" == "301 https://example.com/site"
    check "HTTPS serves the application in redirect mode" contains "$(body -k "${S}/site")" '"https":true'
    stack_survived "the redirect scenario" || true
    stop_stack || fail "Redirect stack shutdown"
fi

use_mode uid
reset_app
if boot_stack "[uid] Redirect mode with APACHE_HTTPS_PORT=${HTTPS_PORT} boots" APACHE_SSL_REDIRECT=true SKIP_COMPOSER_INSTALL=true; then
    check "Redirect goes to APACHE_HTTPS_PORT for every host" bash -c '[[ "$1" == "301 https://localhost:8443/site?a=1" &&
        "$2" == "301 https://example.com:8443/site" ]]' _ \
        "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -A "$UA" "http://localhost:${HTTP_PORT}/site?a=1")" \
        "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -A "$UA" -H 'Host: example.com' "${H}/site")"
    check "HTTPS on the custom port serves the application" contains "$(body -k "${S}/site")" '"https":true'
    stop_stack || fail "Custom port redirect stack shutdown"
fi

#------------------------------------------------------------------------------
# Entrypoint behavior (command mode, root unless stated)
#------------------------------------------------------------------------------
use_mode root
# docker run -e PHP_DISABLE_FUNCTIONS (unset on the host) removes the image default, which supervisord needs; the
# entrypoint restores it, and the comparison with the image ENV catches a drift between both copies of the default
reset_app
fresh_runtime
disable_rc=0
disable_value="$(env -u PHP_DISABLE_FUNCTIONS "${BASE_ENV[@]}" APACHE_SSL_ENABLED=false SKIP_COMPOSER_INSTALL=true \
    /usr/local/bin/entrypoint printenv PHP_DISABLE_FUNCTIONS 2>/dev/null)" || disable_rc=$?
check "Removed PHP_DISABLE_FUNCTIONS falls back to the image default" \
    bash -c '[[ "$1" -eq 0 && "$2" == "$3" ]]' _ "$disable_rc" "$disable_value" "$PHP_DISABLE_FUNCTIONS"
reset_app
fresh_runtime
disable_rc=0
disable_value="$(env "${BASE_ENV[@]}" APACHE_SSL_ENABLED=false SKIP_COMPOSER_INSTALL=true PHP_DISABLE_FUNCTIONS= \
    /usr/local/bin/entrypoint printenv PHP_DISABLE_FUNCTIONS 2>/dev/null)" || disable_rc=$?
check "Empty PHP_DISABLE_FUNCTIONS stays empty" bash -c '[[ "$1" -eq 0 && -z "$2" ]]' _ "$disable_rc" "$disable_value"
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
check "[root] Migrations run as www-data" bash -c '[[ "$1" == *"SMOKE-YII uid=33 args=migrate --interactive=0"* ]]' _ "$ENTRY_OUT"
run_entrypoint "${migration_env[@]}" SMOKE_MIGRATION_FAIL=1 FAIL_ON_MIGRATION_ERROR=false -- echo SMOKE-REACHED
check "FAIL_ON_MIGRATION_ERROR=false continues" entry_reached
run_entrypoint "${migration_env[@]}" SMOKE_MIGRATION_FAIL=1 -- echo SMOKE-REACHED
check "FAIL_ON_MIGRATION_ERROR defaults to true and exits non-zero" entry_aborted

run_entrypoint BUILD_TYPE=prod SKIP_COMPOSER_INSTALL=false -- echo SMOKE-REACHED
check "Explicit SKIP_COMPOSER_INSTALL=false runs Composer in prod" bash -c '[[ "$1" -eq 0 && -f "$2" ]]' _ "$ENTRY_RC" "${APP_DIR}/vendor/autoload.php"
run_entrypoint BUILD_TYPE=dev SKIP_COMPOSER_INSTALL=true -- echo SMOKE-REACHED
check "Explicit SKIP_COMPOSER_INSTALL=true skips Composer in dev" bash -c '[[ "$1" -eq 0 && ! -e "$2" ]]' _ "$ENTRY_RC" "${APP_DIR}/vendor"

run_entrypoint APACHE_SSL_ENABLED=true SSL_AUTO_GENERATE=false SSL_DIR="${WORK_DIR}/no-certs" SKIP_COMPOSER_INSTALL=true -- cat "$APACHE_ENV_FILE"
check "Missing certificates without auto-generation fall back to HTTP-only" \
    bash -c '[[ "$1" -eq 0 && "$2" != *SSL_ENABLED* && "$2" == *"falling back to HTTP-only"* ]]' _ "$ENTRY_RC" "$ENTRY_OUT"

# External certificates: a pair in SSL_DIR, as a mounted directory would provide it
mkdir -p "${WORK_DIR}/certs"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${WORK_DIR}/certs/key.pem" -out "${WORK_DIR}/certs/cert.pem" -days 2 \
    -subj /CN=localhost >/dev/null 2>&1
cp "${WORK_DIR}/certs/cert.pem" "${WORK_DIR}/chain.pem"
chmod 0644 "${WORK_DIR}/certs/cert.pem" "${WORK_DIR}/certs/key.pem" "${WORK_DIR}/chain.pem"
cert_env=(APACHE_SSL_ENABLED=true SSL_AUTO_GENERATE=false SSL_DIR="${WORK_DIR}/certs" SKIP_COMPOSER_INSTALL=true)
run_entrypoint "${cert_env[@]}" SSL_CHAIN_FILE="${WORK_DIR}/chain.pem" -- cat "$APACHE_ENV_FILE"
check "External certificates enable OCSP stapling and the chain file" \
    bash -c '[[ "$1" == *"-D SSL_ENABLED"* && "$1" == *"-D SSL_CHAIN"* && "$1" == *"-D SSL_STAPLING"* ]]' _ "$ENTRY_OUT"
check "apache2ctl configtest with SSL_CHAIN and SSL_STAPLING" apache2ctl configtest
run_entrypoint "${cert_env[@]}" APACHE_DISABLE_OCSP_STAPLING=true -- cat "$APACHE_ENV_FILE"
check "APACHE_DISABLE_OCSP_STAPLING=true disables stapling" bash -c '[[ "$1" == *"-D SSL_ENABLED"* && "$1" != *SSL_STAPLING* ]]' _ "$ENTRY_OUT"

# A key only root can read: a non-root stack explains it and serves HTTP only instead of failing to start
chmod 0600 "${WORK_DIR}/certs/key.pem"
use_mode www-data
run_entrypoint "${cert_env[@]}" -- cat "$APACHE_ENV_FILE"
check "[www-data] Unreadable key is reported and falls back to HTTP-only" bash -c '[[ "$1" -eq 0 &&
    "$2" == *"is not readable by uid=33"* && "$2" == *"falling back to HTTP-only"* && "$2" != *"-D SSL_ENABLED"* ]]' \
    _ "$ENTRY_RC" "$ENTRY_OUT"

run_entrypoint "${migration_env[@]}" -- echo SMOKE-REACHED
check "[www-data] Migrations run as www-data" bash -c '[[ "$1" == *"SMOKE-YII uid=33 args=migrate"* ]]' _ "$ENTRY_OUT"

use_mode uid
run_entrypoint "${migration_env[@]}" -- echo SMOKE-REACHED
check "[uid] Migrations run as UID ${ANY_UID}" bash -c '[[ "$1" == *"SMOKE-YII uid=$2 args=migrate"* ]]' _ "$ENTRY_OUT" "$ANY_UID"

# An application directory owned by another user: Composer is skipped with the reason and the remedy
reset_app
chown -R root:root "$APP_DIR"
run_entrypoint_keep SKIP_COMPOSER_INSTALL=false -- echo SMOKE-REACHED
check "[uid] Not writable application directory is reported with the remedy" bash -c '[[ "$1" -eq 0 && "$2" == *SMOKE-REACHED* &&
    "$2" == *"Composer cannot write to /var/www/app as uid=4242(no passwd entry)"* && "$2" == *"Remedy:"* && ! -e "$3" ]]' \
    _ "$ENTRY_RC" "$ENTRY_OUT" "${APP_DIR}/vendor"

# A port below ip_unprivileged_port_start (1024 in build steps) is refused with the remedy before supervisord starts:
# APACHE_HTTP_PORT always, APACHE_HTTPS_PORT only when SSL is active (scenario B boots HTTP-only with 443)
if [[ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 0)" -gt 443 ]]; then
    reset_app
    fresh_runtime
    ENTRY_RC=0
    ENTRY_OUT="$(as_mode env "${BASE_ENV[@]}" APACHE_HTTP_PORT=80 APACHE_SSL_ENABLED=false SKIP_COMPOSER_INSTALL=true \
        timeout 20 /usr/local/bin/entrypoint 2>&1)" || ENTRY_RC=$?
    check "[uid] Privileged port is refused with the remedy" bash -c '[[ "$1" -eq 1 &&
        "$2" == *"Port 80 is privileged here"* && "$2" == *"APACHE_HTTP_PORT"* ]]' _ "$ENTRY_RC" "$ENTRY_OUT"
    reset_app
    fresh_runtime
    ENTRY_RC=0
    ENTRY_OUT="$(as_mode env "${BASE_ENV[@]}" APACHE_HTTP_PORT=8080 APACHE_HTTPS_PORT=443 SKIP_COMPOSER_INSTALL=true \
        timeout 20 /usr/local/bin/entrypoint 2>&1)" || ENTRY_RC=$?
    check "[uid] Privileged HTTPS port is refused when SSL is active" bash -c '[[ "$1" -eq 1 &&
        "$2" == *"Port 443 is privileged here"* && "$2" == *"set APACHE_HTTPS_PORT"* ]]' _ "$ENTRY_RC" "$ENTRY_OUT"
else
    skip "Privileged port refusal (ports below 1024 are not privileged here)"
fi
use_mode root

#------------------------------------------------------------------------------
# Summary (printed by the EXIT trap)
#------------------------------------------------------------------------------
COMPLETED=true
