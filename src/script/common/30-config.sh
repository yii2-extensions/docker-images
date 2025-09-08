#==============================================================================
# Update configuration
#==============================================================================

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
            local key_re
            key_re="$(printf '%s' "$key" | sed -e 's/[][^$.*/\\+?|(){}-]/\\&/g')"
            local repl
            repl="$(printf '%s %s' "$key" "$value" | sed -e 's/[&|\\/]/\\&/g')"
            if grep -Eq "^[[:space:]]*${key_re}([[:space:]]|$)" "$file" 2>/dev/null; then
                sed -i -E "s|^[[:space:]]*${key_re}([[:space:]]|$).*|${repl}|" "$file"
            else
                echo "${key} ${value}" >> "$file"
            fi
            ;;
        ini)
            local key_re
            key_re="$(printf '%s' "$key" | sed -e 's/[][^$.*/\\+?|(){}-]/\\&/g')"
            local repl
            repl="$(printf '%s = %s' "$key" "$value" | sed -e 's/[&|\\/]/\\&/g')"
            if grep -Eq "^${key_re}[[:space:]]*=" "$file" 2>/dev/null; then
                sed -i -E "s|^${key_re}[[:space:]]*=.*|${repl}|" "$file"
            else
                echo "${key} = ${value}" >> "$file"
            fi
            ;;
        env)
            local key_re
            key_re="$(printf '%s' "$key" | sed -e 's/[][^$.*/\\+?|(){}-]/\\&/g')"
            local repl
            repl="$(printf '%s=%s' "$key" "$value" | sed -e 's/[&|\\/]/\\&/g')"
            if grep -Eq "^[[:space:]]*(export[[:space:]]+)?${key_re}[[:space:]]*=" "$file" 2>/dev/null; then
                sed -i -E "s|^([[:space:]]*(export[[:space:]]+)?)${key_re}[[:space:]]*=.*|\1${repl}|" "$file"
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
