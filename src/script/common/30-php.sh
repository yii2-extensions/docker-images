# =============================================================================
# PHP configure
# =============================================================================
php_configure() {
    log INFO "Configuring PHP and PHP-FPM..."

    local php_version="${PHP_VERSION:-$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')}"
    local php_config_dir="/etc/php/${php_version}"

    # Configure PHP-FPM first
    configure_php_fpm

    # Configure system PHP if we have permissions
    if [[ -w "$php_config_dir" ]]; then
        configure_system_php "$php_version"
    else
        log WARNING "Cannot modify system PHP config - insufficient permissions"
    fi

    log SUCCESS "PHP configuration completed"
}

# =============================================================================
# Configure system PHP settings
# =============================================================================
configure_system_php() {
    local php_version="$1"

    log DEBUG "Configuring system PHP settings..."

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
        [[ -d "$ini_dir" ]] || continue

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
    configure_redis_sessions "$php_version"

    log DEBUG "System PHP configuration applied"
}

# =============================================================================
# Configure Redis sessions
# =============================================================================
configure_redis_sessions() {
    local php_version="$1"

    [[ "${PHP_REDIS_SESSION:-false}" != "true" ]] && return

    if php -r 'exit((int)!extension_loaded("redis"));'; then
        for sapi in apache2 cli; do
            local ini_dir="/etc/php/${php_version}/${sapi}/conf.d"
            [[ -d "$ini_dir" ]] || continue

            local ini="${ini_dir}/99-docker.ini"
            echo "session.save_handler = redis" >> "$ini"
            echo "session.save_path = tcp://${DB_REDIS_HOST:-redis}:${DB_REDIS_PORT:-6379}" >> "$ini"
        done
        log SUCCESS "Redis session handler configured"
    else
        log WARNING "PHP_REDIS_SESSION=true but redis extension not loaded"
    fi
}

# =============================================================================
# Configure PHP-FPM with dynamic environment variables
# =============================================================================
configure_php_fpm() {
    # Check if PHP-FPM is available
    if ! command -v php-fpm >/dev/null 2>&1; then
        log DEBUG "PHP-FPM not available, skipping FPM configuration"
        return 0
    fi

    log DEBUG "Configuring PHP-FPM with dynamic settings..."

    local config_file="/usr/local/etc/php-fpm.d/zz-app.conf"
    [[ ! -f "$config_file" ]] && {
        log DEBUG "PHP-FPM config file not found: $config_file"
        return 0
    }

    # Set default values for PHP-FPM variables
    local fpm_vars=(
        "PHP_FPM_PM:dynamic"
        "PHP_FPM_MAX_CHILDREN:50"
        "PHP_FPM_START_SERVERS:5"
        "PHP_FPM_MIN_SPARE:5"
        "PHP_FPM_MAX_SPARE:35"
        "PHP_FPM_MAX_REQUESTS:500"
        "PHP_MEMORY_LIMIT:256M"
        "PHP_MAX_EXECUTION_TIME:30"
        "PHP_MAX_INPUT_TIME:60"
        "PHP_POST_MAX_SIZE:50M"
        "PHP_UPLOAD_MAX_FILESIZE:50M"
        "PHP_DISPLAY_ERRORS:off"
    )

    # Set defaults for undefined variables
    for var_def in "${fpm_vars[@]}"; do
        IFS=':' read -r var_name default_value <<< "$var_def"
        [[ -z "${!var_name:-}" ]] && export "$var_name=$default_value"
    done

    # Apply environment variable substitution in PHP-FPM config
    local replacements=(
        "s/\\\${PM}/${PHP_FPM_PM}/g"
        "s/\\\${MAX_CHILDREN}/${PHP_FPM_MAX_CHILDREN}/g"
        "s/\\\${START_SERVERS}/${PHP_FPM_START_SERVERS}/g"
        "s/\\\${MIN_SPARE}/${PHP_FPM_MIN_SPARE}/g"
        "s/\\\${MAX_SPARE}/${PHP_FPM_MAX_SPARE}/g"
        "s/\\\${MAX_REQUESTS}/${PHP_FPM_MAX_REQUESTS}/g"
        "s/\\\${MEMORY_LIMIT}/${PHP_MEMORY_LIMIT}/g"
        "s/\\\${MAX_EXECUTION_TIME}/${PHP_MAX_EXECUTION_TIME}/g"
        "s/\\\${MAX_INPUT_TIME}/${PHP_MAX_INPUT_TIME}/g"
        "s/\\\${POST_MAX_SIZE}/${PHP_POST_MAX_SIZE}/g"
        "s/\\\${UPLOAD_MAX_FILESIZE}/${PHP_UPLOAD_MAX_FILESIZE}/g"
        "s/\\\${DISPLAY_ERRORS}/${PHP_DISPLAY_ERRORS}/g"
    )

    for replacement in "${replacements[@]}"; do
        sed -i "$replacement" "$config_file"
    done

    log DEBUG "PHP-FPM configuration applied: PM=$PHP_FPM_PM, Max Children=$PHP_FPM_MAX_CHILDREN"
}
