#!/bin/bash
set -euo pipefail

#==============================================================================
# Microsoft SQL Server Drivers Installation Script
# Installs ODBC Driver and PHP extensions (sqlsrv, pdo_sqlsrv)
#==============================================================================

echo "Installing Microsoft SQL Server drivers..."

# Function to install packages with error handling
install_packages() {
    apt-get update && apt-get install -y --no-install-recommends "$@" \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*
}

# Function to install PECL extension with error handling
install_pecl_extension() {
    local extension="$1"
    local fallback_version="$2"

    echo "Installing PHP $extension extension..."
    if ! printf "\n" | pecl install "$extension"; then
        echo "Warning: $extension installation failed, trying version $fallback_version..."
        if ! printf "\n" | pecl install "$extension-$fallback_version"; then
            echo "Error: failed to install $extension (including fallback $fallback_version)." >&2
            exit 1
        fi
    fi
}

# Install prerequisites
install_packages \
    gnupg \
    curl \
    apt-transport-https \
    lsb-release \
    libgssapi-krb5-2

# Add Microsoft's GPG key and repository (using Debian 12 for compatibility)
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
echo "deb [arch=amd64,armhf,arm64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list

# Install ODBC Driver and tools
apt-get update
ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
    msodbcsql18 \
    unixodbc-dev \
    odbcinst \
    || {
        echo "Warning: Some MSSQL packages failed, trying minimal installation..."
        ACCEPT_EULA=Y apt-get install -y --no-install-recommends unixodbc-dev odbcinst
    }

# Try to install optional tools
ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-tools18 || echo "Warning: mssql-tools18 not available"

# Install PHP development packages
PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
install_packages php${PHP_VER}-dev php-pear build-essential

# Install PHP extensions
pecl channel-update pecl.php.net
install_pecl_extension "sqlsrv" "5.11.1"
install_pecl_extension "pdo_sqlsrv" "5.11.1"

# Clean up development packages
apt-get remove -y --purge gnupg apt-transport-https php${PHP_VER}-dev build-essential \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

echo "SQL Server drivers installation completed!"
echo "Note: Extensions will be enabled in the Dockerfile"
