#!/bin/bash
#==============================================================================
# Runtime helpers: failure policy, running user and runtime state
#
# The stack runs as the container user: www-data by default, any UID given
# with --user, or root as an explicit opt-in (--user root), where Apache and
# PHP-FPM drop their workers to www-data. Runtime state (pid files, sockets,
# the Apache runtime environment, generated certificates, PHP sessions and
# temporary files) lives under YII2_RUN_DIR and is created at every start for
# the running user, so a tmpfs mounted on /run or /run/yii2 works in every mode.
#==============================================================================

readonly YII2_RUN_DIR=/run/yii2

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

is_root() {
    [[ "$(id -u)" == "0" ]]
}

# Prints the running user for messages; an arbitrary UID has no name.
current_user_label() {
    local name
    name="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f1 || true)"
    printf 'uid=%s(%s) gid=%s' "$(id -u)" "${name:-no passwd entry}" "$(id -g)"
}

# Runs a command as www-data when root, or as the current user otherwise. The environment is preserved.
run_as_app_user() {
    if is_root; then
        setpriv --reuid=www-data --regid=www-data --init-groups -- "$@"
    else
        "$@"
    fi
}

# Succeeds when the absolute path is neither a symbolic link nor below one, so root can act on it by name.
path_is_canonical() {
    [[ "$(realpath -m -- "$1")" == "$1" ]]
}

# Logs how to give the running user write access to the application directory.
app_directory_remedy() {
    log INFO "Remedy: give $(current_user_label) write access (on a Linux host: sudo chown -R $(id -u):$(id -g) <project>),"
    log INFO "or run the container as the owner of the files (--user \"\$(id -u):\$(id -g)\", Compose user:),"
    log INFO "or start it as root (--user root) so FIX_PERMS=true hands the directory to www-data"
}

runtime_unwritable() {
    log ERROR "Runtime directory ${YII2_RUN_DIR} is not usable by $(current_user_label): $1"
    log INFO "Remedy: mount a tmpfs there that this user can write (--tmpfs /run/yii2:mode=1777)"
    exit 1
}

# Creates the runtime directory tree for the running user.
#
# Root removes and recreates every directory it uses, owned by root and not writable by www-data, so nothing that root
# sources, executes, loads or writes by path can be prepared or replaced by www-data; only the PHP session and temporary
# directories, used by the www-data workers, belong to www-data. Any other user owns the whole tree.
runtime_prepare() {
    local dir

    if [[ ! -d "$YII2_RUN_DIR" ]] && ! mkdir -p "$YII2_RUN_DIR" 2>/dev/null; then
        runtime_unwritable "cannot create it"
    fi

    if is_root; then
        chown root:root "$YII2_RUN_DIR"
        chmod 0755 "$YII2_RUN_DIR"
        for dir in apache php supervisor ssl sessions tmp; do
            if [[ -L "${YII2_RUN_DIR}/${dir}" ]]; then
                rm -f -- "${YII2_RUN_DIR:?}/${dir}"
            fi
        done
        rm -rf -- "${YII2_RUN_DIR:?}/apache" "${YII2_RUN_DIR:?}/php" "${YII2_RUN_DIR:?}/supervisor" "${YII2_RUN_DIR:?}/ssl"
        install -d -m 0755 -o root -g root "${YII2_RUN_DIR}/apache" "${YII2_RUN_DIR}/apache/socks" \
            "${YII2_RUN_DIR}/php" "${YII2_RUN_DIR}/supervisor"
        install -d -m 0700 -o root -g root "${YII2_RUN_DIR}/ssl"
        install -d -m 0700 -o www-data -g www-data "${YII2_RUN_DIR}/sessions" "${YII2_RUN_DIR}/tmp"
        export YII2_FPM_LISTEN_OWNER=www-data
        return 0
    fi

    for dir in apache php supervisor ssl sessions tmp; do
        if [[ ! -d "${YII2_RUN_DIR}/${dir}" ]] && ! mkdir -m 0700 "${YII2_RUN_DIR}/${dir}" 2>/dev/null; then
            runtime_unwritable "cannot create ${YII2_RUN_DIR}/${dir}"
        fi
        if [[ ! -O "${YII2_RUN_DIR}/${dir}" || ! -w "${YII2_RUN_DIR}/${dir}" ]]; then
            runtime_unwritable "${YII2_RUN_DIR}/${dir} belongs to another user"
        fi
    done
    chmod 0755 "${YII2_RUN_DIR}/apache" "${YII2_RUN_DIR}/php" "${YII2_RUN_DIR}/supervisor"
    # apache2ctl would create this directory itself and chown it to www-data, which only root can do
    mkdir -p "${YII2_RUN_DIR}/apache/socks"
    rm -f -- "${YII2_RUN_DIR}/ssl/cert.pem" "${YII2_RUN_DIR}/ssl/key.pem"
    export YII2_FPM_LISTEN_OWNER=""
}
