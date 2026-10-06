#!/bin/bash
#==============================================================================
# install-extensions - installs PHP extensions into the slim image
#
# Usage (as root, for example in a derived Dockerfile):
#   RUN install-extensions amqp sockets
#
# Accepts every extension name and version syntax of install-php-extensions (for example `xdebug-3.4.5`).
# Downloads the PHP source the image was built from, verifies its SHA-256 checksum, builds the extensions, then
# removes the compiler toolchain, the PHP source and every build-only package while keeping the shared libraries
# the extensions load. Fails when a binary or an extension is left with an unresolved library, or when PHP
# reports a startup problem.
#
# Internal commands, used by the image build:
#   install-extensions --purge <auto-package-list>   remove the toolchain, keep the runtime libraries
#   install-extensions --verify                      check the toolchain is gone and every ELF file resolves
#==============================================================================
set -euo pipefail

readonly PHP_SOURCE_FILE=/usr/local/lib/yii2-docker/php-source.env
readonly PHP_TARBALL=/usr/src/php.tar.xz
readonly TOOLCHAIN=(autoconf c++ cc cpp g++ gcc ld make pkg-config re2c)

die() {
    printf 'install-extensions: %s\n' "$1" >&2
    exit 1
}

# Prints the directories holding PHP, its extensions, Apache, Node.js and the vendor client libraries.
binary_dirs() {
    local dir
    printf '%s\n' "$@"
    for dir in /opt/microsoft /usr/lib/oracle; do
        if [[ -d "$dir" ]]; then
            printf '%s\n' "$dir"
        fi
    done
}

# Marks as manually installed every package providing a shared library that a binary or an extension loads.
mark_runtime_libraries() {
    local dirs libs patterns packages

    mapfile -t dirs < <(binary_dirs /usr/local /usr/sbin/apache2 /usr/lib/apache2/modules)
    libs="$(
        find "${dirs[@]}" -type f \( -perm /111 -o -name '*.so*' \) -exec ldd '{}' ';' 2>/dev/null \
            | awk '/=> \// { print $(NF - 1) }' \
            | sort -u
    )"
    [[ -n "$libs" ]] || die "No shared library found to keep."
    # Resolve symlinks the installer adds (libaio.so.1 for Oracle) and skip libraries shipped outside dpkg
    patterns="$(
        xargs -r readlink -f <<<"$libs" \
            | awk '!/^\/(usr\/local|usr\/lib\/oracle|opt)\// { sub("^/(usr/)?", ""); print "*" $0 }' \
            | sort -u
    )"
    packages="$(xargs -r dpkg-query --search <<<"$patterns" | grep -v '^diversion by ' | cut -d: -f1 | tr -s ', ' '\n' | sort -u)"
    xargs -r apt-mark manual <<<"$packages" >/dev/null
}

# Usage: purge_toolchain <auto-package-list>
# Restores the auto-installed marks saved before the extensions were built, keeps the runtime libraries and removes
# the toolchain, every package only it needed, the PHP source and the package caches.
purge_toolchain() {
    local auto_list="$1"
    local deps

    [[ -r "$auto_list" ]] || die "Package list ${auto_list} not readable."
    : "${PHPIZE_DEPS:?PHPIZE_DEPS is not set}"

    # The installer marks some of its packages, toolchain included, as manually installed
    xargs -r apt-mark auto <"$auto_list" >/dev/null
    mark_runtime_libraries

    # libc-dev is a virtual package, its provider libc6-dev must be named explicitly
    read -r -a deps <<<"$PHPIZE_DEPS"
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false "${deps[@]}" libc6-dev

    apt-get clean
    rm -rf \
        /root/.cache \
        /root/.composer \
        /tmp/* \
        /usr/src/php \
        "$PHP_TARBALL" \
        "${PHP_TARBALL}.asc" \
        /var/cache/apt/* \
        /var/lib/apt/lists/* \
        /var/log/apt/* \
        /var/log/dpkg.log \
        /var/tmp/*
    rm -f "$auto_list"
}

# Fails when the toolchain or the PHP source is present, an ELF file has an unresolved library, or PHP reports a
# startup problem.
verify() {
    local tool dirs files file magic output modules
    local checked=0 broken=0

    for tool in "${TOOLCHAIN[@]}"; do
        if command -v "$tool" >/dev/null; then
            printf 'Toolchain leftover: %s\n' "$tool" >&2
            broken=1
        fi
    done
    if [[ -e /usr/libexec/gcc || -e /usr/include/stdio.h || -e "$PHP_TARBALL" || -e /usr/src/php ]]; then
        printf 'Compiler support files or PHP source left behind\n' >&2
        broken=1
    fi

    mapfile -t dirs < <(binary_dirs /usr/local/bin /usr/local/sbin /usr/sbin/apache2 /usr/lib/apache2/modules \
        "$(php-config --extension-dir)")
    files="$(find "${dirs[@]}" -type f)"
    while IFS= read -r file; do
        magic=""
        LC_ALL=C IFS= read -r -n 4 magic <"$file" || true
        [[ "$magic" == $'\x7fELF' ]] || continue
        checked=$((checked + 1))
        if ! output="$(ldd "$file" 2>&1)"; then
            [[ "$output" == *"not a dynamic executable"* ]] && continue
            printf 'ldd failed for %s:\n%s\n' "$file" "$output" >&2
            broken=1
            continue
        fi
        if [[ "$output" == *"not found"* ]]; then
            printf 'Unresolved libraries in %s:\n%s\n' "$file" "$(grep 'not found' <<<"$output")" >&2
            broken=1
        fi
    done <<<"$files"
    printf 'Checked %d ELF files\n' "$checked"
    [[ "$checked" -gt 10 ]] || die "Too few ELF files checked (${checked})."

    modules="$(php -d display_startup_errors=1 -d error_reporting=-1 -m 2>&1)"
    if grep -Eq 'Warning|Fatal error|Unable to load' <<<"$modules"; then
        printf 'PHP startup problems:\n%s\n' "$modules" >&2
        broken=1
    fi
    php-fpm -t

    [[ "$broken" -eq 0 ]] || die "Verification failed."
}

# Downloads the PHP source recorded at image build time and verifies its checksum.
fetch_php_source() {
    local key value php_url="" php_sha256="" php_version=""

    [[ -r "$PHP_SOURCE_FILE" ]] || die "${PHP_SOURCE_FILE} not found; the image does not record its PHP source."
    while IFS='=' read -r key value; do
        case "$key" in
        PHP_URL) php_url="$value" ;;
        PHP_SHA256) php_sha256="$value" ;;
        PHP_VERSION) php_version="$value" ;;
        esac
    done <"$PHP_SOURCE_FILE"
    [[ -n "$php_url" && "$php_sha256" =~ ^[0-9a-f]{64}$ ]] || die "Malformed ${PHP_SOURCE_FILE}."
    [[ "$(php -n -r 'echo PHP_VERSION;')" == "$php_version" ]] || die "Running PHP is not ${php_version}."

    curl -fsSL --retry 3 -o "$PHP_TARBALL" "$php_url"
    printf '%s *%s\n' "$php_sha256" "$PHP_TARBALL" | sha256sum -c --quiet - || die "Checksum mismatch for ${php_url}."
}

# Prints the installed packages, sorted.
installed_packages() {
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' | awk '/^ii/ { print $2 }' | sort -u
}

install_extensions() {
    local auto_list deps before

    [[ "$(id -u)" == "0" ]] || die "Must run as root."
    command -v install-php-extensions >/dev/null || die "install-php-extensions not found."

    : "${PHPIZE_DEPS:?PHPIZE_DEPS is not set}"
    read -r -a deps <<<"$PHPIZE_DEPS"

    auto_list="$(mktemp /usr/src/apt-auto-packages.XXXXXX)"
    apt-mark showauto >"$auto_list"
    fetch_php_source

    # install-php-extensions expects the upstream toolchain. Everything this step adds is recorded as auto-installed,
    # so the purge removes it again even when the installer marks part of it (cpp, binutils, pkgconf) as manual.
    before="$(installed_packages)"
    apt-get update
    apt-get install -y --no-install-recommends "${deps[@]}"
    comm -13 <(printf '%s\n' "$before") <(installed_packages) >>"$auto_list"

    install-php-extensions "$@"
    purge_toolchain "$auto_list"
    verify
}

case "${1:-}" in
--purge)
    [[ $# -eq 2 ]] || die "Usage: install-extensions --purge <auto-package-list>"
    purge_toolchain "$2"
    ;;
--verify)
    verify
    ;;
"" | -h | --help)
    printf 'Usage: install-extensions <extension> [extension...]\n' >&2
    exit 2
    ;;
-*)
    die "Unknown option: $1"
    ;;
*)
    install_extensions "$@"
    ;;
esac
