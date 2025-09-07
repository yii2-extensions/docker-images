#!/bin/bash
set -euo pipefail

#==============================================================================
# Docker Entrypoint - Generic for all services
#==============================================================================

# Load common functionalities
for script in /usr/local/bin/common/*.sh; do
    [[ -f "$script" ]] && source "$script"
done

# Main execution
main() {
    print_banner

    # Check if we need to escalate privileges for initialization
    if [[ "$(id -u)" != "0" ]]; then
        # We're running as non-root (www-data), but we need root privileges for initialization
        # Use exec with sudo to restart as root, then switch back to www-data for the final process
        if command -v sudo >/dev/null 2>&1; then
            log INFO "Escalating to root for system initialization..."
            exec sudo -E "$0" "$@"
        else
            log WARNING "Running as non-root user without sudo - some initialization steps may fail"
        fi
    fi

    # Only run initialization if we're root
    if [[ "$(id -u)" == "0" ]]; then
        log INFO "Running as root - performing system configuration..."

        # Setup directories
        setup_directories

        # SSL setup for Apache with HTTP/2 (non-blocking)
        if [[ "${SERVICE_TYPE:-}" == "apache-fpm" ]] && command -v apache2 >/dev/null 2>&1; then
            source /usr/local/bin/common/30-ssl.sh || log WARNING "SSL setup failed, continuing without SSL"
        fi

        # PHP configuration via environment variables (if PHP is installed)
        if command -v php >/dev/null 2>&1; then
            configure_php
        fi

        # Set final permissions
        if [[ -d "/var/www/app" ]]; then
            log INFO "Setting final permissions..."
            chown -R www-data:www-data /var/www/app/runtime 2>/dev/null || true
            chown -R www-data:www-data /var/www/app/web/assets 2>/dev/null || true
        fi
    else
        log INFO "Running as non-root user: $(id -un)"
    fi

    # Wait for databases if configured
    wait_for_databases

    # Composer install
    composer_install

    # Run migrations
    yii_run_migrations

    # Create health endpoint
    health_create_endpoint

    log SUCCESS "Container initialization complete!"
    log INFO "Starting services..."
    echo "" >&2

    # If no command specified, start supervisor
    if [[ $# -eq 0 ]]; then
        exec supervisord -c /etc/supervisor/supervisord.conf
    else
        exec "$@"
    fi
}

# Wait for databases (simplified)
wait_for_databases() {
    [[ "${SKIP_DB_WAIT:-false}" == "true" ]] && return

    # Auto-detect if we should wait based on environment
    local should_wait=false
    [[ "${WAIT_FOR_SERVICES:-false}" == "true" ]] && should_wait=true
    [[ "${YII_ENV:-}" == "test" ]] && should_wait=true

    [[ "$should_wait" == "false" ]] && return

    # Wait for configured databases
    for db_type in MYSQL PGSQL REDIS MONGODB MSSQL ORACLE; do
        local host_var="DB_${db_type}_HOST"
        local port_var="DB_${db_type}_PORT"

        if [[ -n "${!host_var:-}" ]]; then
            local default_port
            case $db_type in
                MYSQL)   default_port=3306 ;;
                PGSQL)   default_port=5432 ;;
                REDIS)   default_port=6379 ;;
                MONGODB) default_port=27017 ;;
                MSSQL)   default_port=1433 ;;
                ORACLE)  default_port=1521 ;;
            esac

            wait_for_service "${!host_var}" "${!port_var:-$default_port}" "$db_type"
        fi
    done
}

# Execute main function
main "$@"
