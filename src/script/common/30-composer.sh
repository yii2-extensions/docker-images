# =============================================================================
# Handle composer dependencies
# =============================================================================
composer_install() {
    [[ "${SKIP_COMPOSER_INSTALL:-false}" == "true" ]] && {
        log INFO "Skipping Composer install"
        return
    }

    [[ ! -f "/var/www/app/composer.json" ]] && {
        log DEBUG "No composer.json found, skipping Composer"
        return
    }

    if [[ -d "/var/www/app/vendor" ]] && [[ "${FORCE_COMPOSER_INSTALL:-false}" != "true" ]]; then
        log INFO "Vendor directory exists, skipping Composer install"
        return
    fi

    log INFO "Installing Composer dependencies..."
    cd /var/www/app || { log ERROR "App directory not found: /var/www/app"; return 1; }

    # Build composer command
    local cmd="composer install --no-interaction --no-progress --optimize-autoloader"

    if [[ "${YII_ENV:-}" == "prod" || "${BUILD_TYPE:-}" == "prod" ]]; then
        cmd+=" --no-dev --classmap-authoritative"
    fi

    [[ "${COMPOSER_NO_SCRIPTS:-false}" == "true" ]] && cmd+=" --no-scripts"
    [[ -n "${COMPOSER_EXTRA_FLAGS:-}" ]] && cmd+=" ${COMPOSER_EXTRA_FLAGS}"

    # Execute as www-data if we're root, otherwise run directly
    if [[ "$(id -u)" == "0" ]]; then
        su www-data -s /bin/bash -c "$cmd" && result=0 || result=1
    else
        eval "$cmd" && result=0 || result=1
    fi

    if [[ $result -eq 0 ]]; then
        log SUCCESS "Composer dependencies installed"
        [[ -f "yii" ]] && chmod +x yii
    else
        log ERROR "Composer install failed"
        [[ "${FAIL_ON_COMPOSER_ERROR:-false}" == "true" ]] && exit 1
        return 1
    fi
}
