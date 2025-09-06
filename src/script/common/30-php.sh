#!/bin/bash
set -euo pipefail

# =============================================================================
# PHP configure
# =============================================================================
php_configure() {
    log INFO "Configuring PHP..."

    local php_version="${PHP_VERSION:-$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')}"
    local php_config_dir="/etc/php/${php_version}"
    if [[ ! -w "$php_config_dir" ]]; then
        log WARNING "Cannot modify PHP config - insufficient permissions"
        return 0
    fi

    local PHP_SETTINGS=(
        "date.timezone:PHP_DATE_TIMEZONE"
        "default_socket_timeout:PHP_DEFAULT_SOCKET_TIMEOUT"
        "display_errors:PHP_DISPLAY_ERRORS"
        "error_reporting:PHP_ERROR_REPORTING"
        "expose_php:PHP_EXPOSE"
        "log_errors:PHP_LOG_ERRORS"
        "max_execution_time:PHP_MAX_EXECUTION_TIME"
        "max_file_uploads:PHP_MAX_FILE_UPLOADS"
        "max_input_time:PHP_MAX_INPUT_TIME"
        "max_input_vars:PHP_MAX_INPUT_VARS"
        "memory_limit:PHP_MEMORY_LIMIT"
        "opcache.enable:PHP_OPCACHE_ENABLE"
        "opcache.max_accelerated_files:PHP_OPCACHE_MAX_ACCELERATED_FILES"
        "opcache.memory_consumption:PHP_OPCACHE_MEMORY_CONSUMPTION"
        "post_max_size:PHP_POST_MAX_SIZE"
        "session.save_handler:PHP_SESSION_SAVE_HANDLER"
        "session.save_path:PHP_SESSION_SAVE_PATH"
        "upload_max_filesize:PHP_UPLOAD_MAX_FILESIZE"
    )

    for sapi in apache2 cli; do
        local ini_dir="/etc/php/${php_version}/${sapi}/conf.d"
        mkdir -p "$ini_dir"
        local ini="${ini_dir}/99-docker.ini"
        {
            echo "; Docker PHP Configuration - Generated at $(date '+%Y-%m-%d %H:%M:%S')"
            echo
        } > "$ini"

        for setting in "${PHP_SETTINGS[@]}"; do
            IFS=':' read -r key env_var <<< "$setting"
            if [[ -n "${!env_var:-}" ]]; then
                echo "${key} = ${!env_var}" >> "$ini"
                log DEBUG "Set ${key} = ${!env_var}"
            fi
        done
    done

    # Redis session configuration
    if [[ "${PHP_REDIS_SESSION:-false}" == "true" ]]; then
        if php -r 'exit((int)!extension_loaded("redis"));'; then
            for sapi in apache2 cli; do
                local ini="/etc/php/${php_version}/${sapi}/conf.d/99-docker.ini"
                echo "session.save_handler = redis" >> "$ini"
                echo "session.save_path = tcp://${DB_REDIS_HOST:-redis}:${DB_REDIS_PORT:-6379}" >> "$ini"
            done
            log SUCCESS "Redis session handler configured"
        else
            log WARNING "PHP_REDIS_SESSION=true but redis extension not loaded; skipping session handler setup"
        fi
    fi

    log SUCCESS "PHP configuration applied"
}
