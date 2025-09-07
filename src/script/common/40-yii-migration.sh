# =============================================================================
# Run migrations
# =============================================================================
yii_run_migrations() {
    [[ "${YII_RUN_MIGRATIONS:-false}" != "true" ]] && return
    [[ ! -f "/var/www/app/yii" ]] && { log WARNING "Yii console not found"; return; }
    [[ "${YII_ENV:-}" == "test" ]] && { log INFO "Test environment, skipping migrations"; return; }

    log INFO "Running database migrations..."
    cd /var/www/app

    if gosu www-data php yii migrate --interactive=0; then
        log SUCCESS "Migrations completed"
    else
        log ERROR "Migration failed"
        [[ "${FAIL_ON_MIGRATION_ERROR:-true}" == "true" ]] && exit 1
    fi
}
