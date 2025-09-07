# =============================================================================
# Setup directories
# =============================================================================
setup_directories() {
    log INFO "Setting up application directories..."

    local app_dirs=(
        "/var/www/app/runtime"
        "/var/www/app/web/assets"
        "/var/www/app/web/uploads"
        "/var/www/.composer"
        "/var/www/.npm"
        "/var/www/.cache"
        "/var/www/.config"
    )

    local service_dirs=(
        "/var/run/php"
        "/var/lib/php/sessions"
        "/var/lib/php/tmp"
    )

    # Add custom directories if specified
    if [[ -n "${CUSTOM_DIRECTORIES:-}" ]]; then
        IFS=',' read -ra CUSTOM_DIRS <<< "$CUSTOM_DIRECTORIES"
        app_dirs+=("${CUSTOM_DIRS[@]}")
    fi

    # Create and set permissions for all directories
    for dir in "${app_dirs[@]}" "${service_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log DEBUG "Created: $dir"
        fi
        chown www-data:www-data "$dir" 2>/dev/null || true
    done

    # Set specific permissions for key directories
    chmod 775 /var/www/app/runtime 2>/dev/null || true
    chmod 775 /var/www/app/web/assets 2>/dev/null || true
    
    log SUCCESS "Application and service directories prepared"
}
