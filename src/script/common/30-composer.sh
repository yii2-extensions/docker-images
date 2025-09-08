#==============================================================================
# Handle composer dependencies
#==============================================================================

composer_install() {
    # Skip if explicitly disabled
    [[ "${SKIP_COMPOSER_INSTALL:-false}" == "true" ]] && {
        log INFO "Skipping Composer install"
        return
    }

    # Check for composer.json
    [[ ! -f "/var/www/app/composer.json" ]] && {
        log DEBUG "No composer.json found, skipping Composer"
        return
    }

    # Skip if vendor exists and not forced
    if [[ -d "/var/www/app/vendor" ]] && [[ "${FORCE_COMPOSER_INSTALL:-false}" != "true" ]]; then
        log INFO "Vendor directory exists, skipping Composer install"
        return
    fi

    log INFO "Installing Composer dependencies..."
    cd /var/www/app || {
        log ERROR "App directory not found: /var/www/app"
        return 1
    }

    # Build composer command as array (prevents injection/quoting issues)
    local -a cmd=(
        composer
        install
        --no-interaction
        --no-progress
        --optimize-autoloader
    )

    # Add environment-specific flags
    if [[ "${YII_ENV:-}" == "prod" || "${BUILD_TYPE:-}" == "prod" ]]; then
        cmd+=(
            --no-dev
            --classmap-authoritative
        )
        log DEBUG "Using production flags for Composer"
    fi

    # Add optional no-scripts flag
    [[ "${COMPOSER_NO_SCRIPTS:-false}" == "true" ]] && {
        cmd+=(--no-scripts)
        log DEBUG "Disabling Composer scripts"
    }

    # Handle extra flags with validation
    if [[ -n "${COMPOSER_EXTRA_FLAGS:-}" ]]; then
        # Validate that flags start with - or --
        if [[ ! "${COMPOSER_EXTRA_FLAGS}" =~ ^[[:space:]]*-{1,2} ]]; then
            log WARN "Invalid COMPOSER_EXTRA_FLAGS format, skipping: ${COMPOSER_EXTRA_FLAGS}"
        else
            # Safely parse extra flags
            IFS=' ' read -ra extra_flags <<< "${COMPOSER_EXTRA_FLAGS}"
            cmd+=("${extra_flags[@]}")
            log DEBUG "Added extra Composer flags: ${COMPOSER_EXTRA_FLAGS}"
        fi
    fi

    # Set timeout if configured (default: 10 minutes)
    local timeout_cmd=()
    if [[ -n "${COMPOSER_TIMEOUT:-}" ]]; then
        timeout_cmd=(timeout --preserve-status "${COMPOSER_TIMEOUT}")
    elif command -v timeout &>/dev/null; then
        timeout_cmd=(timeout --preserve-status 600)
    fi

    # Prepare error logging
    local error_log="/tmp/composer_error_$$.log"
    local result=0

    # Execute command with appropriate user context
    if [[ "$(id -u)" == "0" ]]; then
        log DEBUG "Running as root, switching to www-data user"

        # Try different user-switching methods in order of preference
        if command -v runuser &>/dev/null; then
            # runuser is most secure (doesn't use PAM by default)
            log DEBUG "Using runuser for user switch"
            "${timeout_cmd[@]}" runuser -u www-data -- "${cmd[@]}" 2>"$error_log" || result=$?

        elif command -v gosu &>/dev/null; then
            # gosu is designed for containers
            log DEBUG "Using gosu for user switch"
            "${timeout_cmd[@]}" gosu www-data "${cmd[@]}" 2>"$error_log" || result=$?

        elif command -v sudo &>/dev/null; then
            # sudo with explicit user
            log DEBUG "Using sudo for user switch"
            "${timeout_cmd[@]}" sudo -u www-data "${cmd[@]}" 2>"$error_log" || result=$?

        else
            # Fallback to su with proper escaping
            log DEBUG "Using su for user switch (fallback)"
            local escaped_cmd
            escaped_cmd=$(printf '%q ' "${timeout_cmd[@]}" "${cmd[@]}")
            su www-data -s /bin/bash -c "$escaped_cmd" 2>"$error_log" || result=$?
        fi
    else
        # Run directly as current user
        log DEBUG "Running as non-root user: $(whoami)"
        "${timeout_cmd[@]}" "${cmd[@]}" 2>"$error_log" || result=$?
    fi

    # Handle results
    if [[ $result -eq 0 ]]; then
        log SUCCESS "Composer dependencies installed successfully"

        # Make yii executable if it exists
        [[ -f "yii" ]] && {
            chmod +x yii
            log DEBUG "Made yii executable"
        }

        # Clean up error log
        rm -f "$error_log"
    else
        log ERROR "Composer install failed with exit code: $result"

        # Log error details if available
        if [[ -s "$error_log" ]]; then
            log ERROR "Error details:"
            while IFS= read -r line; do
                log ERROR "  $line"
            done < "$error_log"
        fi

        # Clean up error log
        rm -f "$error_log"

        # Exit if configured to fail on error
        if [[ "${FAIL_ON_COMPOSER_ERROR:-false}" == "true" ]]; then
            log ERROR "Exiting due to FAIL_ON_COMPOSER_ERROR=true"
            exit 1
        fi

        return 1
    fi
}
