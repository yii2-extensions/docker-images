#!/bin/bash
set -euo pipefail

# =============================================================================
# Wait for Service
# =============================================================================
wait_for_service() {
    local host=$1
    local port=$2
    local service=$3
    local timeout=${4:-${SERVICE_WAIT_TIMEOUT:-30}}
    local elapsed=0
    local check_interval=1

    log INFO "Waiting for ${service} at ${host}:${port} (timeout: ${timeout}s)..."

    while ! (exec 3<>/dev/tcp/${host}/${port}) 2>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            log ERROR "${service} failed to respond within ${timeout} seconds"
            [[ "${FAIL_ON_SERVICE_TIMEOUT:-false}" == "true" ]] && exit 1
            return 1
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))

        if [[ $((elapsed % 5)) -eq 0 ]]; then
            log DEBUG "Still waiting for ${service}... (${elapsed}/${timeout}s)"
        fi
    done

    log SUCCESS "${service} is ready (${elapsed}s)"
    return 0
}
