#!/bin/bash
set -euo pipefail

# =============================================================================
# Docker Entrypoint
# =============================================================================

# =============================================================================
# Load common functionalities
# =============================================================================
source /usr/local/bin/common/01-globals.sh
source /usr/local/bin/common/10-log.sh
source /usr/local/bin/common/20-health.sh
source /usr/local/bin/common/30-banner.sh
source /usr/local/bin/common/30-composer.sh
source /usr/local/bin/common/30-config.sh
source /usr/local/bin/common/30-directories.sh
source /usr/local/bin/common/30-php.sh
source /usr/local/bin/common/30-service.sh
source /usr/local/bin/common/30-shutdown.sh
source /usr/local/bin/common/40-yii-migration.sh

# =============================================================================
# Load service module
# =============================================================================
load_service_module() {
    local service_type="${SERVICE_TYPE:-apache}"
    local module_paths=(
        "/usr/local/bin/configure-${service_type}.sh"
        "/var/www/app/docker/scripts/configure-${service_type}.sh"
        "/docker/scripts/configure-${service_type}.sh"
    )

    for module_path in "${module_paths[@]}"; do
        if [[ -f "$module_path" ]]; then
            log INFO "Loading ${service_type} configuration module from $module_path"
            # shellcheck disable=SC1090
            source "$module_path"
            return 0
        fi
    done

    log WARNING "${service_type} configuration module not found, using fallback"
    return 1
}

# =============================================================================
# Generic Service Configuration (fallback)
# =============================================================================
configure_service_fallback() {
    log INFO "Using fallback service configuration..."

    # Basic Apache fallback
    if command -v apache2ctl >/dev/null 2>&1; then
        log INFO "Configuring Apache (fallback implementation)..."

        local apache_conf="/etc/apache2/apache2.conf"
        if [[ -w "$apache_conf" ]]; then
            [[ -n "${APACHE_KEEP_ALIVE_TIMEOUT:-}" ]] && update_config "KeepAliveTimeout" "${APACHE_KEEP_ALIVE_TIMEOUT}" "$apache_conf" "apache"
            [[ -n "${APACHE_KEEP_ALIVE:-}" ]] && update_config "KeepAlive" "${APACHE_KEEP_ALIVE}" "$apache_conf" "apache"
            [[ -n "${APACHE_LOG_LEVEL:-}" ]] && update_config "LogLevel" "${APACHE_LOG_LEVEL}" "$apache_conf" "apache"
            [[ -n "${APACHE_SERVER_NAME:-}" ]] && update_config "ServerName" "${APACHE_SERVER_NAME:-localhost}" "$apache_conf" "apache"
            log SUCCESS "Apache configuration updated (fallback)"
        else
            log WARNING "Cannot modify Apache config - insufficient permissions"
        fi
    fi
}

# =============================================================================
# Configure service
# =============================================================================
configure_service() {
    if declare -f configure_service_impl >/dev/null 2>&1; then
        log INFO "Using modular service configuration..."
        configure_service_impl
    else
        configure_service_fallback
    fi
}

# =============================================================================
# Service Verification (generic)
# =============================================================================
verify_service() {
    if declare -f verify_service_impl >/dev/null 2>&1; then
        verify_service_impl
    elif command -v apache2ctl >/dev/null 2>&1; then
        log INFO "Verifying Apache configuration..."
        if apache2ctl -t 2>&1 | grep -q "Syntax OK"; then
            log SUCCESS "Apache configuration valid"
        else
            log ERROR "Apache configuration invalid"
            apache2ctl -t
            exit 1
        fi
    else
        log INFO "No service verification available"
    fi
}

# =============================================================================
# Wait for databases
# =============================================================================
wait_for_databases() {
    [[ "${SKIP_DB_WAIT:-false}" == "true" ]] && return

    local should_wait=false
    [[ "${WAIT_FOR_SERVICES:-false}" == "true" ]] && should_wait=true
    [[ "${BUILD_TYPE:-}" == "full" ]] && should_wait=true
    [[ "${YII_ENV:-}" == "test" ]] && should_wait=true

    [[ "$should_wait" == "false" ]] && return

    [[ -n "${DB_MSSQL_HOST:-}" ]] && wait_for_service "${DB_MSSQL_HOST}" "${DB_MSSQL_PORT:-1433}" "SQL Server"
    [[ -n "${DB_MYSQL_HOST:-}" ]] && wait_for_service "${DB_MYSQL_HOST}" "${DB_MYSQL_PORT:-3306}" "MySQL"
    [[ -n "${DB_ORACLE_HOST:-}" ]] && wait_for_service "${DB_ORACLE_HOST}" "${DB_ORACLE_PORT:-1521}" "Oracle"
    [[ -n "${DB_PGSQL_HOST:-}" ]] && wait_for_service "${DB_PGSQL_HOST}" "${DB_PGSQL_PORT:-5432}" "PostgreSQL"
    [[ -n "${DB_REDIS_HOST:-}" ]] && wait_for_service "${DB_REDIS_HOST}" "${DB_REDIS_PORT:-6379}" "Redis"
    [[ -n "${DB_MONGODB_HOST:-}" ]] && wait_for_service "${DB_MONGODB_HOST}" "${DB_MONGODB_PORT:-27017}" "MongoDB"
}

# =============================================================================
# Main execution
# =============================================================================
main() {
    print_banner

    # Load service-specific module
    load_service_module

    if [ "$(id -u)" = "0" ]; then
        log INFO "Running as root - performing system configuration..."

        # Setup service environment if available
        if declare -f setup_service_environment >/dev/null 2>&1; then
            setup_service_environment
        fi

        # Setup service directories if available
        if declare -f setup_service_directories >/dev/null 2>&1; then
            setup_service_directories
        fi

        configure_service
        php_configure
        setup_directories
        verify_service

        # Final permissions
        if [[ -d "/var/www/app" ]]; then
            log INFO "Setting final permissions..."
            chown -R www-data:www-data /var/www/app/runtime 2>/dev/null || true
            chown -R www-data:www-data /var/www/app/web/assets 2>/dev/null || true
        fi
    fi

    wait_for_databases
    composer_install
    yii_run_migrations
    health_create_endpoint

    log SUCCESS "Container initialization complete!"
    log INFO "Starting service..."
    echo "" >&2

    if [[ $# -eq 0 && -x "$(command -v apache2ctl)" ]]; then
        set -- apache2ctl -DFOREGROUND
    fi

    exec "$@"
}

main "$@"
