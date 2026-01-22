#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/01-mssql-odbc.sh"

main() {
    mssql_add_apt_repo
    mssql_install_odbc_runtime

    read -r -a phpize_deps <<<"${PHPIZE_DEPS:-}"
    apt-get install -y --no-install-recommends unixodbc-dev "${phpize_deps[@]}"

    printf '\n' | pecl install sqlsrv-5.12.0

    local php_version_id
    php_version_id="$(php -r 'echo PHP_VERSION_ID;')"

    if [[ "${php_version_id}" -ge 80500 ]]; then
        cd /tmp
        pecl download pdo_sqlsrv-5.12.0
        tar -xf pdo_sqlsrv-5.12.0.tgz
        rm -f pdo_sqlsrv-5.12.0.tgz

        cd pdo_sqlsrv-5.12.0

        sed -i 's/= dbh->error_mode/= (enum pdo_error_mode) dbh->error_mode/' pdo_dbh.cpp
        sed -i 's/zval_ptr_dtor( &dbh->query_stmt_zval );/OBJ_RELEASE(dbh->query_stmt_obj);dbh->query_stmt_obj=NULL;/' php_pdo_sqlsrv_int.h

        phpize
        ./configure --with-php-config="$(command -v php-config)"
        make -j"$(nproc)"
        make install
        rm -rf /tmp/pdo_sqlsrv-5.12.0
    else
        printf '\n' | pecl install pdo_sqlsrv-5.12.0
    fi

    docker-php-ext-enable sqlsrv pdo_sqlsrv

    apt-get purge -y --auto-remove gnupg unixodbc-dev "${phpize_deps[@]}"
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/pear /tmp/* /var/tmp/*
}

main "$@"
