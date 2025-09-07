
#==============================================================================
# Run migrations
#==============================================================================

yii_run_migrations() {
    [[ "${YII_RUN_MIGRATIONS:-false}" != "true" ]] && return
    [[ ! -f "/var/www/app/yii" ]] && { log WARNING "Yii console not found"; return; }
    [[ "${YII_ENV:-}" == "test" ]] && { log INFO "Test environment, skipping migrations"; return; }

    log INFO "Running database migrations..."
    cd /var/www/app || {
        log ERROR "Failed to cd to /var/www/app"
        [[ "${FAIL_ON_MIGRATION_ERROR:-true}" == "true" ]] && exit 1 || return 1
    }

    # Execute as www-data if we're root, otherwise run directly
    if [[ "$(id -u)" == "0" ]]; then
        su www-data -s /bin/bash -c "php yii migrate --interactive=0" && result=0 || result=1
    else
        php yii migrate --interactive=0 && result=0 || result=1
    fi

    if [[ $result -eq 0 ]]; then
        log SUCCESS "Migrations completed"
    else
        log ERROR "Migration failed"
        [[ "${FAIL_ON_MIGRATION_ERROR:-true}" == "true" ]] && exit 1
        return 1
    fi
}
