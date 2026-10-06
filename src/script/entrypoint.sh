#!/bin/bash
set -euo pipefail

#==============================================================================
# Docker Entrypoint - Generic for all services
#==============================================================================

# Load common functionalities
for script in /usr/local/lib/yii2-docker/common/*.sh; do
    source "$script"
done

# Main execution
main() {
    print_banner

    if [[ "$(id -u)" == "0" ]]; then
        log INFO "Running as root - performing system configuration..."

        # Setup directories
        setup_directories

        # Apache defines, SSL certificates and health endpoints
        if [[ "${SERVICE_TYPE:-}" == "apache-fpm" ]] && command -v apache2 >/dev/null 2>&1; then
            apache_configure
        fi

        # Set final permissions
        if [[ -d "/var/www/app" ]]; then
            log INFO "Setting final permissions..."
            chown -R www-data:www-data /var/www/app/runtime 2>/dev/null || true
            chown -R www-data:www-data /var/www/app/web/assets 2>/dev/null || true
        fi
    else
        log WARNING "Running as non-root user $(id -un): skipping system configuration (directories, Apache, SSL, permissions)"
    fi

    # Wait for databases if configured
    wait_for_databases

    # Composer install
    composer_install

    # Run migrations
    yii_run_migrations

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
    if [[ "${SKIP_DB_WAIT:-false}" == "true" ]]; then
        return 0
    fi

    # Auto-detect if we should wait based on environment
    local should_wait=false
    [[ "${WAIT_FOR_SERVICES:-false}" == "true" ]] && should_wait=true
    [[ "${YII_ENV:-}" == "test" ]] && should_wait=true

    if [[ "$should_wait" == "false" ]]; then
        return 0
    fi

    # Wait for configured databases
    local db_type
    for db_type in MYSQL PGSQL REDIS MONGODB MSSQL ORACLE; do
        local host_var="DB_${db_type}_HOST"
        local port_var="DB_${db_type}_PORT"

        if [[ -n "${!host_var:-}" ]]; then
            local default_port
            case $db_type in
            MYSQL) default_port=3306 ;;
            PGSQL) default_port=5432 ;;
            REDIS) default_port=6379 ;;
            MONGODB) default_port=27017 ;;
            MSSQL) default_port=1433 ;;
            ORACLE) default_port=1521 ;;
            esac

            if ! wait_for_service "${!host_var}" "${!port_var:-$default_port}" "$db_type"; then
                fail_or_continue FAIL_ON_SERVICE_TIMEOUT false "${db_type} is not reachable"
            fi
        fi
    done
}

# Execute main function
main "$@"
