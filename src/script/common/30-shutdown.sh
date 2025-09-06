#!/bin/bash
set -euo pipefail

# =============================================================================
# Shutdown Handler
# =============================================================================
shutdown_handler() {
    log INFO "Received shutdown signal, gracefully stopping service..."
    if [[ -n "${SERVICE_PID}" ]]; then
        kill -TERM "${SERVICE_PID}" 2>/dev/null || true
        wait "${SERVICE_PID}" 2>/dev/null || true
    fi
    log SUCCESS "Service stopped gracefully"
    exit 0
}

trap shutdown_handler SIGTERM SIGINT SIGQUIT
