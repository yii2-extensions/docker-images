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

    # Give www-data write access (opt-in; selective to reduce churn)
    if [[ "${FIX_PERMS:-true}" == "true" ]]; then
        find /var/www/app ! -user www-data -exec chown www-data:www-data {} +
        find /var/www/app -type d -exec chmod u+rwx,g+rwx {} +
        find /var/www/app -type f -exec chmod u+rw,g+rw {} +
    fi

    # Create and configure npm cache directory for www-data
    mkdir -p /var/www/.npm
    chown -R www-data:www-data /var/www/.npm

    # Install dependencies with proper environment variables
    if [[ "${YII_ENV:-}" == "prod" || "${BUILD_TYPE:-}" == "prod" ]]; then
        # Production: exclude dev dependencies and optimize autoloader
        log DEBUG "Using production flags for Composer"
        gosu www-data env \
            HOME=/var/www \
            COMPOSER_HOME=/var/www/.composer \
            COMPOSER_CACHE_DIR=/var/www/.composer/cache \
            npm_config_cache=/var/www/.npm \
            composer install --ansi --quiet --no-dev --no-interaction --no-progress --optimize-autoloader --prefer-dist
    else
        # Development: include dev dependencies
        log DEBUG "Using development flags for Composer"
        gosu www-data env \
            HOME=/var/www \
            COMPOSER_HOME=/var/www/.composer \
            COMPOSER_CACHE_DIR=/var/www/.composer/cache \
            npm_config_cache=/var/www/.npm \
            composer install --ansi --quiet --no-interaction --no-progress --optimize-autoloader --prefer-dist
    fi

    local result=$?

    if [[ $result -eq 0 ]]; then
        log SUCCESS "Composer dependencies installed successfully"

        # Make yii executable if it exists
        [[ -f "/var/www/app/yii" ]] && {
            chmod +x /var/www/app/yii
            log DEBUG "Made yii executable"
        }
    else
        log ERROR "Composer install failed with exit code: $result"

        # Exit if configured to fail on error
        if [[ "${FAIL_ON_COMPOSER_ERROR:-false}" == "true" ]]; then
            log ERROR "Exiting due to FAIL_ON_COMPOSER_ERROR=true"
            exit 1
        fi

        return 1
    fi
}
