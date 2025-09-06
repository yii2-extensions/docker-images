#!/bin/bash
set -euo pipefail

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
    cd /var/www/app

    local cmd="composer install --no-interaction --no-progress --optimize-autoloader"

    if [[ "${YII_ENV}" == "prod" ]] || [[ "${BUILD_TYPE}" == "prod" ]]; then
        cmd="$cmd --no-dev --classmap-authoritative"
    fi

    [[ "${COMPOSER_NO_SCRIPTS:-false}" == "true" ]] && cmd="$cmd --no-scripts"
    [[ -n "${COMPOSER_EXTRA_FLAGS}" ]] && cmd="$cmd ${COMPOSER_EXTRA_FLAGS}"

    if gosu www-data $cmd; then
        log SUCCESS "Composer dependencies installed"
        [[ -f "yii" ]] && chmod +x yii
    else
        log ERROR "Composer install failed"
        [[ "${FAIL_ON_COMPOSER_ERROR:-false}" == "true" ]] && exit 1
    fi
}
