#!/bin/bash
set -euo pipefail

# =============================================================================
# Apache script modular configuration
# =============================================================================

# =============================================================================
# Configure service implementation
# =============================================================================
configure_service_impl() {
    log INFO "Configuring Apache runtime settings..."

    # Only apply dynamic configuration changes based on environment variables
    apply_dynamic_config

    # Ensure the site is enabled
    enable_yii2_site

    log SUCCESS "Apache runtime configuration completed"
}

#==============================================================================
# Apply dynamic configuration based on environment variables
#==============================================================================
apply_dynamic_config() {
    local apache_conf="/etc/apache2/apache2.conf"
    local vhost_conf="/etc/apache2/sites-available/yii2.conf"

    # Only modify if we have write permissions
    if [[ ! -w "$apache_conf" ]]; then
        log WARNING "Cannot modify Apache config - insufficient permissions"
        return 0
    fi

    # Apply dynamic settings only if environment variables are set
    local config_updated=false

    # Runtime settings that can be overridden
    if [[ -n "${APACHE_TIMEOUT:-}" ]]; then
        sed -i -E "s|^[[:space:]]*Timeout[[:space:]]+.*|Timeout ${APACHE_TIMEOUT}|" "$apache_conf"
        log DEBUG "Set Apache Timeout = ${APACHE_TIMEOUT}"
        config_updated=true
    fi

    if [[ -n "${APACHE_KEEP_ALIVE_TIMEOUT:-}" ]]; then
        sed -i -E "s|^[[:space:]]*KeepAliveTimeout[[:space:]]+.*|KeepAliveTimeout ${APACHE_KEEP_ALIVE_TIMEOUT}|" "$apache_conf"
        log DEBUG "Set KeepAliveTimeout = ${APACHE_KEEP_ALIVE_TIMEOUT}"
        config_updated=true
    fi

    if [[ -n "${APACHE_MAX_KEEP_ALIVE_REQUESTS:-}" ]]; then
        sed -i -E "s|^[[:space:]]*MaxKeepAliveRequests[[:space:]]+.*|MaxKeepAliveRequests ${APACHE_MAX_KEEP_ALIVE_REQUESTS}|" "$apache_conf"
        log DEBUG "Set MaxKeepAliveRequests = ${APACHE_MAX_KEEP_ALIVE_REQUESTS}"
        config_updated=true
    fi

    if [[ -n "${APACHE_LOG_LEVEL:-}" ]]; then
        sed -i -E "s|^[[:space:]]*LogLevel[[:space:]]+.*|LogLevel ${APACHE_LOG_LEVEL}|" "$apache_conf"
        log DEBUG "Set LogLevel = ${APACHE_LOG_LEVEL}"
        config_updated=true
    fi

    if [[ -n "${APACHE_SERVER_NAME:-}" ]]; then
        sed -i -E "s|^[[:space:]]*ServerName[[:space:]]+.*|ServerName ${APACHE_SERVER_NAME}|" "$apache_conf"
        log DEBUG "Set ServerName = ${APACHE_SERVER_NAME}"
        config_updated=true
    fi

    # Document root override (if needed)
    if [[ -n "${APACHE_DOCUMENT_ROOT:-}" && -f "$vhost_conf" && -w "$vhost_conf" ]]; then
        sed -i "s|DocumentRoot .*|DocumentRoot ${APACHE_DOCUMENT_ROOT}|" "$vhost_conf"
        sed -i "s|<Directory /var/www/app/web>|<Directory ${APACHE_DOCUMENT_ROOT}>|" "$vhost_conf"
        log DEBUG "Set DocumentRoot = ${APACHE_DOCUMENT_ROOT}"
        config_updated=true
    fi

    if [[ "$config_updated" == "true" ]]; then
        log SUCCESS "Dynamic Apache configuration applied"
    else
        log INFO "Using default Apache configuration (no overrides specified)"
    fi
}

#==============================================================================
# Enable Yii2 site
#==============================================================================
enable_yii2_site() {
    if [[ -f "/etc/apache2/sites-available/yii2.conf" ]]; then
        if a2ensite yii2 >/dev/null 2>&1; then
            log DEBUG "Yii2 site enabled"
        else
            log WARNING "Failed to enable Yii2 site (may already be enabled)"
        fi
    else
        log ERROR "Yii2 site configuration not found"
        return 1
    fi
}

# =============================================================================
# Verify service implementation
# =============================================================================
verify_service_impl() {
    local status=0
    check_required_modules || status=1
    verify_sites || status=1
    if [[ $status -eq 0 ]]; then
        log SUCCESS "Apache configuration verification passed"
        return 0
    else
        log WARNING "Apache verification finished with issues"
        return 1
    fi
}

# =============================================================================
# Check required Apache modules
# =============================================================================
check_required_modules() {
    local required_modules=("rewrite" "headers" "deflate" "expires")
    local missing_modules=()

    for module in "${required_modules[@]}"; do
        if ! apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
            missing_modules+=("$module")
        fi
    done

    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        log WARNING "Missing required Apache modules: ${missing_modules[*]}"
        return 1
    fi

    log DEBUG "All required Apache modules are loaded"
    return 0
}

# =============================================================================
# Verify site configurations
# =============================================================================
verify_sites() {
    if [[ ! -f "/etc/apache2/sites-enabled/yii2.conf" ]]; then
        log WARNING "Yii2 site is not enabled"
        return 1
    fi

    # Check if document root exists
    local doc_root=$(grep "DocumentRoot" /etc/apache2/sites-enabled/yii2.conf | awk '{print $2}')
    if [[ -n "$doc_root" && ! -d "$doc_root" ]]; then
        log WARNING "DocumentRoot directory does not exist: $doc_root"
        return 1
    fi

    log DEBUG "Site configuration verified"
    return 0
}

# =============================================================================
# Setup service environment
# =============================================================================
setup_service_environment() {
    log INFO "Setting up Apache environment..."

    # Export Apache runtime variables with defaults
    export APACHE_RUN_USER=${APACHE_RUN_USER:-www-data}
    export APACHE_RUN_GROUP=${APACHE_RUN_GROUP:-www-data}
    export APACHE_LOG_DIR=${APACHE_LOG_DIR:-/var/log/apache2}
    export APACHE_LOCK_DIR=${APACHE_LOCK_DIR:-/var/lock/apache2}
    export APACHE_PID_FILE=${APACHE_PID_FILE:-/var/run/apache2/apache2.pid}
    export APACHE_RUN_DIR=${APACHE_RUN_DIR:-/var/run/apache2}

    log SUCCESS "Apache environment configured"
}

# =============================================================================
# Setup service directories
# =============================================================================
setup_service_directories() {
    log INFO "Setting up Apache runtime directories..."

    local dirs=(
        "${APACHE_RUN_DIR}"
        "${APACHE_LOG_DIR}"
        "${APACHE_LOCK_DIR}"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log DEBUG "Created: $dir"
        fi
    done

    # Set ownership if running as root
    if [[ "$(id -u)" == "0" ]]; then
        chown "${APACHE_RUN_USER}:${APACHE_RUN_GROUP}" "${dirs[@]}" 2>/dev/null || true
        chmod 755 "${APACHE_LOG_DIR}" 2>/dev/null || true
        log SUCCESS "Apache directories configured with proper ownership"
    else
        log INFO "Apache directories created (ownership not changed - not root)"
    fi
}

# =============================================================================
# Graceful restart
# =============================================================================
graceful_restart() {
    log INFO "Performing graceful Apache restart..."

    if apache2ctl graceful; then
        log SUCCESS "Apache gracefully restarted"
    else
        log ERROR "Apache graceful restart failed"
        return 1
    fi
}

# =============================================================================
# Check service status
# =============================================================================
check_service_status() {
    log INFO "Checking Apache status..."

    if pgrep apache2 >/dev/null; then
        log SUCCESS "Apache is running"

        # Show process info if debug is enabled
        if [[ "${DEBUG_ENTRYPOINT:-false}" == "true" ]]; then
            local apache_processes=$(pgrep -c apache2)
            log DEBUG "Apache processes: $apache_processes"
        fi
    else
        log WARNING "Apache is not running"
        return 1
    fi
}

# =============================================================================
# Main execution logic
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-configure}" in
        "configure")
            configure_service_impl
            ;;
        "verify")
            verify_service_impl
            ;;
        "setup-env")
            setup_service_environment
            ;;
        "setup-dirs")
            setup_service_directories
            ;;
        "restart")
            graceful_restart
            ;;
        "status")
            check_service_status
            ;;
        "full")
            setup_service_environment
            setup_service_directories
            configure_service_impl
            verify_service_impl
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  configure    - Apply dynamic configuration (default)"
            echo "  verify       - Verify Apache configuration"
            echo "  setup-env    - Setup environment variables"
            echo "  setup-dirs   - Setup runtime directories"
            echo "  restart      - Graceful restart"
            echo "  status       - Check service status"
            echo "  full         - Complete setup and verification"
            echo "  help         - Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  APACHE_TIMEOUT                  - Request timeout (default: 300)"
            echo "  APACHE_KEEP_ALIVE_TIMEOUT       - KeepAlive timeout (default: 5)"
            echo "  APACHE_MAX_KEEP_ALIVE_REQUESTS  - Max KeepAlive requests (default: 100)"
            echo "  APACHE_LOG_LEVEL                - Log level (default: warn)"
            echo "  APACHE_SERVER_NAME              - Server name (default: localhost)"
            echo "  APACHE_DOCUMENT_ROOT           - Document root override"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
fi
