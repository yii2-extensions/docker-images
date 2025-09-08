#==============================================================================
# Shutdown Handler
#==============================================================================

shutdown_handler() {
    log INFO "Received shutdown signal, gracefully stopping service..."
    if [[ -n "${SERVICE_PID:-}" ]]; then
        if kill -0 "${SERVICE_PID}" 2>/dev/null; then
            kill -TERM "${SERVICE_PID}" 2>/dev/null || true
            wait "${SERVICE_PID}" 2>/dev/null || true
        fi
    fi
}

trap shutdown_handler SIGTERM SIGINT SIGQUIT
