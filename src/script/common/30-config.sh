#!/bin/bash
set -euo pipefail

# =============================================================================
# Update configuration
# =============================================================================
update_config() {
    local key="$1"
    local value="$2"
    local file="$3"
    local format="${4:-ini}"

    if [[ ! -f "$file" ]]; then
        log DEBUG "Creating config file: $file"
        mkdir -p "$(dirname "$file")"
        touch "$file"
    fi

    case $format in
        apache)
            if grep -Eq "^[[:space:]]*${key}([[:space:]]|$)" "$file" 2>/dev/null; then
                sed -i -E "s|^[[:space:]]*${key}([[:space:]]|$).*|${key} ${value}|" "$file"
            else
                echo "${key} ${value}" >> "$file"
            fi
            ;;
        ini)
            if grep -Eq "^${key}[[:space:]]*=" "$file" 2>/dev/null; then
                sed -i -E "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
            else
                echo "${key} = ${value}" >> "$file"
            fi
            ;;
        env)
            if grep -q "^${key}=" "$file" 2>/dev/null; then
                sed -i "s|^${key}=.*|${key}=${value}|" "$file"
            else
                echo "${key}=${value}" >> "$file"
            fi
            ;;
        *)
            log WARNING "Unsupported config format: ${format}"
            return 1
    esac

    log DEBUG "Config updated: ${key} in ${file}"
}
