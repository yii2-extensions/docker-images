# =============================================================================
# Setup directories
# =============================================================================
setup_directories() {
    log INFO "Setting up application directories..."

    local dirs=(
        "/var/www/app/runtime"
        "/var/www/app/web/assets"
        "/var/www/app/web/uploads"
        "/var/www/.composer"
        "/var/www/.npm"
        "/var/www/.cache"
        "/var/www/.config"
    )

    if [[ -n "${CUSTOM_DIRECTORIES:-}" ]]; then
        IFS=',' read -ra CUSTOM_DIRS <<< "$CUSTOM_DIRECTORIES"
        dirs+=("${CUSTOM_DIRS[@]}")
    fi

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chown www-data:www-data "$dir" 2>/dev/null || true
            log DEBUG "Created: $dir"
        fi
    done

    chmod 775 /var/www/app/runtime 2>/dev/null || true
    chmod 775 /var/www/app/web/assets 2>/dev/null || true
    log SUCCESS "Directories prepared"
}
