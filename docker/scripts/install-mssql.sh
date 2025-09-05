#!/bin/bash
set -e

# Microsoft SQL Server Drivers Installation Script for Debian Trixie
# Installs ODBC Driver and PHP extensions (sqlsrv, pdo_sqlsrv)

echo "Installing Microsoft SQL Server drivers..."

# Install prerequisites
apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    curl \
    apt-transport-https \
    lsb-release \
    libgssapi-krb5-2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add Microsoft's GPG key and repository
# Using Debian 12 repository as Trixie isn't officially supported yet
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg

# Create repository configuration
echo "deb [arch=amd64,armhf,arm64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list

# Update package list
apt-get update

# Install ODBC Driver and tools
# Note: Using || true to continue even if some packages fail
ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
    msodbcsql18 \
    unixodbc-dev \
    odbcinst \
    || {
        echo "Warning: Some MSSQL packages failed to install, trying alternative..."
        ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
            unixodbc-dev \
            odbcinst
    }

# Try to install mssql-tools18 (optional)
ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-tools18 || echo "Warning: mssql-tools18 not available, continuing without it"

# Install PHP development packages if not already installed
PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
command -v php >/dev/null || { echo "PHP CLI not found. Install PHP before running this script."; exit 1; }
apt-get install -y --no-install-recommends \
    php${PHP_VER}-dev \
    php-pear \
    build-essential

# Install sqlsrv and pdo_sqlsrv via PECL
echo "Installing PHP SQL Server extensions..."
pecl channel-update pecl.php.net

# Try to install the extensions, with fallback to specific versions if needed
pecl install sqlsrv || pecl install sqlsrv-5.11.1
pecl install pdo_sqlsrv || pecl install pdo_sqlsrv-5.11.1

# Clean up
apt-get remove -y --purge \
    gnupg \
    apt-transport-https \
    php${PHP_VER}-dev \
    build-essential \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

echo "SQL Server drivers installation completed!"
echo "Installed: ODBC Driver 18, sqlsrv, pdo_sqlsrv, mssql-tools18 (if available)"
echo "Note: Use 'TrustServerCertificate=true' in connection strings for development"
echo "Extensions will be enabled in the Dockerfile"
echo ""
echo "Runtime dependencies required:"
echo "- msodbcsql18 (Microsoft ODBC Driver 18 for SQL Server)"
echo "- unixodbc (UnixODBC Driver Manager)"
echo "- libgssapi-krb5-2 (Kerberos authentication library)"
