#!/bin/bash
#==============================================================================
# Setup directories
#
# Root creates the writable application directories and hands them to
# www-data, but never acts on a path that is or passes through a symbolic
# link, because the application directory is controlled by the application.
# Any other user creates what it can and explains what it cannot.
#==============================================================================

setup_directories() {
    log INFO "Setting up application directories..."

    local -a app_dirs=(
        "/var/www/app/runtime"
        "/var/www/app/web/assets"
        "/var/www/app/web/uploads"
    )

    # Add custom directories if specified
    if [[ -n "${CUSTOM_DIRECTORIES:-}" ]]; then
        local -a custom_dirs=()
        IFS=',' read -ra custom_dirs <<<"$CUSTOM_DIRECTORIES"
        app_dirs+=("${custom_dirs[@]%/}")
    fi

    local dir
    if ! is_root; then
        local -a unwritable=()
        for dir in "${app_dirs[@]}"; do
            if [[ ! -d "$dir" ]] && ! mkdir -p "$dir" 2>/dev/null; then
                unwritable+=("$dir")
            elif [[ -d "$dir" && ! -w "$dir" ]]; then
                unwritable+=("$dir")
            fi
        done
        if [[ ${#unwritable[@]} -gt 0 ]]; then
            log WARNING "Application directories not writable by $(current_user_label): ${unwritable[*]}"
            app_directory_remedy
            return 0
        fi
        log SUCCESS "Application directories prepared"
        return 0
    fi

    app_dirs+=("/var/www/.composer" "/var/www/.npm" "/var/www/.cache" "/var/www/.config")
    for dir in "${app_dirs[@]}"; do
        if ! path_is_canonical "$dir"; then
            log WARNING "Skipping ${dir}: it is or passes through a symbolic link"
            continue
        fi
        if [[ ! -d "$dir" ]]; then
            if ! mkdir -p "$dir" 2>/dev/null; then
                log WARNING "Cannot create ${dir} (read-only file system?)"
                continue
            fi
            log DEBUG "Created: $dir"
        fi
        chown -h www-data:www-data "$dir" 2>/dev/null || true
    done

    # Set specific permissions for key directories
    for dir in /var/www/app/runtime /var/www/app/web/assets; do
        if [[ -d "$dir" ]] && path_is_canonical "$dir"; then
            chmod 775 "$dir" 2>/dev/null || true
        fi
    done

    log SUCCESS "Application directories prepared"
}

# Root only: hands the writable application directories to www-data, recursively and without following links.
fix_app_permissions() {
    local dir
    for dir in /var/www/app/runtime /var/www/app/web/assets; do
        if [[ -d "$dir" ]] && path_is_canonical "$dir"; then
            chown -R -P www-data:www-data "$dir" 2>/dev/null || true
        fi
    done
}
