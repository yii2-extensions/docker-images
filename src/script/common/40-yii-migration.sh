#!/bin/bash
#==============================================================================
# Run migrations
#==============================================================================

yii_run_migrations() {
    if [[ "${YII_RUN_MIGRATIONS:-false}" != "true" ]]; then
        return 0
    fi

    if [[ ! -f "/var/www/app/yii" ]]; then
        log WARNING "Yii console not found"
        return 0
    fi

    if [[ "${YII_ENV:-}" == "test" ]]; then
        log INFO "Test environment, skipping migrations"
        return 0
    fi

    log INFO "Running database migrations..."

    # Execute as www-data if we're root, otherwise run directly
    local result=0
    (
        cd /var/www/app || exit 1
        run_as_app_user php yii migrate --interactive=0
    ) || result=$?

    if [[ $result -ne 0 ]]; then
        fail_or_continue FAIL_ON_MIGRATION_ERROR true "Migration failed with exit code ${result}"
        return 0
    fi

    log SUCCESS "Migrations completed"
}
