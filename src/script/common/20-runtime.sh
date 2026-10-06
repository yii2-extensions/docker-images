#!/bin/bash
#==============================================================================
# Runtime helpers: failure policy and privilege drop
#==============================================================================

# Applies a FAIL_ON_* policy: exits when the flag is true, otherwise logs and continues.
# Usage: fail_or_continue <FLAG_NAME> <default true|false> <message>
fail_or_continue() {
    local flag_name="$1"
    local default="$2"
    local message="$3"
    local value="${!flag_name:-$default}"

    if [[ "$value" == "true" ]]; then
        log ERROR "${message}; exiting (${flag_name}=true)"
        exit 1
    fi

    log WARNING "${message}; continuing (${flag_name}=${value})"
    return 0
}

# Runs a command as www-data when root, or as the current user otherwise. The environment is preserved.
run_as_app_user() {
    if [[ "$(id -u)" == "0" ]]; then
        setpriv --reuid=www-data --regid=www-data --init-groups -- "$@"
    else
        "$@"
    fi
}
