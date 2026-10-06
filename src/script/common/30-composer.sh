#!/bin/bash
#==============================================================================
# Handle composer dependencies
#==============================================================================

composer_install() {
    # Explicit value wins; otherwise skip by default in prod builds (dependencies belong in the application image)
    local skip="${SKIP_COMPOSER_INSTALL:-}"
    if [[ -z "$skip" ]]; then
        if [[ "${BUILD_TYPE:-}" == "prod" ]]; then
            skip=true
        else
            skip=false
        fi
    fi

    if [[ "$skip" == "true" ]]; then
        log INFO "Skipping Composer install (SKIP_COMPOSER_INSTALL=${SKIP_COMPOSER_INSTALL:-unset, default for ${BUILD_TYPE:-unknown} build})"
        return 0
    fi

    # Check for composer.json
    if [[ ! -f "/var/www/app/composer.json" ]]; then
        log DEBUG "No composer.json found, skipping Composer"
        return 0
    fi

    # Skip if vendor exists and not forced
    if [[ -d "/var/www/app/vendor" ]] && [[ "${FORCE_COMPOSER_INSTALL:-false}" != "true" ]]; then
        log INFO "Vendor directory exists, skipping Composer install"
        return 0
    fi

    log INFO "Installing Composer dependencies..."

    # Give www-data write access (opt-out; enabled by default)
    if [[ "${FIX_PERMS:-true}" == "true" ]] && [[ "$(id -u)" == "0" ]]; then
        chown -R www-data:www-data /var/www/app
        chmod -R g+rwX /var/www/app
    fi

    local -a flags=(--ansi --no-interaction --no-progress --optimize-autoloader --prefer-dist)
    if [[ "${YII_ENV:-}" == "prod" || "${BUILD_TYPE:-}" == "prod" ]]; then
        # Production: exclude dev dependencies
        log DEBUG "Using production flags for Composer"
        flags+=(--no-dev)
    else
        log DEBUG "Using development flags for Composer"
    fi

    local result=0
    (
        cd /var/www/app || exit 1
        run_as_app_user env \
            HOME=/var/www \
            COMPOSER_HOME=/var/www/.composer \
            COMPOSER_CACHE_DIR=/var/www/.composer/cache \
            npm_config_cache=/var/www/.npm \
            composer install "${flags[@]}"
    ) || result=$?

    if [[ $result -ne 0 ]]; then
        fail_or_continue FAIL_ON_COMPOSER_ERROR false "Composer install failed with exit code ${result}"
        return 0
    fi

    log SUCCESS "Composer dependencies installed successfully"

    # Make yii executable if it exists
    if [[ -f "/var/www/app/yii" ]]; then
        chmod +x /var/www/app/yii 2>/dev/null || true
        log DEBUG "Made yii executable"
    fi
}
