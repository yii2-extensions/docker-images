#!/bin/bash
set -euo pipefail

mssql_add_apt_repo() {
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl gnupg

    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
    echo 'deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main' >/etc/apt/sources.list.d/mssql-release.list
}

mssql_install_odbc_runtime() {
    apt-get update
    ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc
}
