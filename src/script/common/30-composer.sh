# =============================================================================
# Handle composer dependencies
# =============================================================================
composer_install() {
    if [[ "${SKIP_COMPOSER_INSTALL:-false}" == "true" ]]; then
        log INFO "Skipping Composer install"
        return
    fi

    if [[ ! -f "/var/www/app/composer.json" ]]; then
        log DEBUG "No composer.json found, skipping Composer"
        return
    fi

    if [[ -d "/var/www/app/vendor" ]] && [[ "${FORCE_COMPOSER_INSTALL:-false}" != "true" ]]; then
        log INFO "Vendor directory exists, skipping Composer install"
        return
    fi

    log INFO "Installing Composer dependencies..."
    # Run inside app dir; fail fast if missing
    cd /var/www/app || { log ERROR "App directory not found: /var/www/app"; return 1; }

    local -a cmd=(composer install --no-interaction --no-progress --optimize-autoloader)

    if [[ "${YII_ENV:-}" == "prod" || "${BUILD_TYPE:-}" == "prod" ]]; then
        cmd+=(--no-dev --classmap-authoritative)
    fi

    [[ "${COMPOSER_NO_SCRIPTS:-false}" == "true" ]] && cmd+=(--no-scripts)
    if [[ -n "${COMPOSER_EXTRA_FLAGS:-}" ]]; then
        # shellcheck disable=SC2206
        read -r -a extras <<< "${COMPOSER_EXTRA_FLAGS}"
        cmd+=("${extras[@]}")
    fi

    if gosu www-data "${cmd[@]}"; then
        log SUCCESS "Composer dependencies installed"
        [[ -f "yii" ]] && chmod +x yii
    else
        log ERROR "Composer install failed"
        [[ "${FAIL_ON_COMPOSER_ERROR:-false}" == "true" ]] && exit 1
    fi
}
