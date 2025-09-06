#!/bin/bash
set -euo pipefail

# Oracle Instant Client Installation Script for Debian Trixie
# Version: 21.x (Latest LTS)

echo "Installing Oracle Instant Client and PHP extensions..."

# Install dependencies
apt-get update && apt-get install -y --no-install-recommends \
    libaio1t64 \
    wget \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Define Oracle version
ORACLE_VERSION=21.13.0.0.0
ORACLE_BASE_URL=https://download.oracle.com/otn_software/linux/instantclient/2113000

# Create Oracle directory
mkdir -p /opt/oracle
cd /opt/oracle

# Download Oracle Instant Client packages
echo "Downloading Oracle Instant Client ${ORACLE_VERSION}..."
wget -q ${ORACLE_BASE_URL}/instantclient-basic-linux.x64-${ORACLE_VERSION}dbru.zip
wget -q ${ORACLE_BASE_URL}/instantclient-sdk-linux.x64-${ORACLE_VERSION}dbru.zip

# Extract packages
unzip -q instantclient-basic-linux.x64-${ORACLE_VERSION}dbru.zip
unzip -q instantclient-sdk-linux.x64-${ORACLE_VERSION}dbru.zip

# Clean up zip files
rm -f *.zip

# Create symbolic links
cd /opt/oracle/instantclient_21_13
ln -sf libclntsh.so.21.1 libclntsh.so
ln -sf libocci.so.21.1 libocci.so

# Update library path
echo "/opt/oracle/instantclient_21_13" > /etc/ld.so.conf.d/oracle-instantclient.conf
ldconfig

# Set environment variables (with proper LD_LIBRARY_PATH handling)
export ORACLE_HOME=/opt/oracle/instantclient_21_13
export LD_LIBRARY_PATH="$ORACLE_HOME:${LD_LIBRARY_PATH:-}"

# Install OCI8 and PDO_OCI PHP extensions via PECL
echo "Installing PHP OCI8 extension..."

# Update PECL channel first
pecl channel-update pecl.php.net

# Install OCI8 with proper configuration
printf "instantclient,/opt/oracle/instantclient_21_13\n" | pecl install oci8 || {
    echo "Warning: OCI8 installation via PECL failed, trying specific version..."
    printf "instantclient,/opt/oracle/instantclient_21_13\n" | pecl install oci8-3.4.0 || {
        echo "Error: OCI8 installation failed completely"
        exit 1
    }
}

echo "Installing PHP PDO_OCI extension..."

# For PHP 8.4+, both OCI8 and PDO_OCI have been moved to PECL
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION.'.'.PHP_RELEASE_VERSION;")
PHP_MAJOR=$(php -r "echo PHP_MAJOR_VERSION;")
PHP_MINOR=$(php -r "echo PHP_MINOR_VERSION;")

echo "Detected PHP version: $PHP_VERSION"

cd /tmp

if { [ "$PHP_MAJOR" -gt 8 ] ; } || { [ "$PHP_MAJOR" -eq 8 ] && [ "$PHP_MINOR" -ge 4 ] ; }; then
    echo "PHP 8.4+ detected, installing PDO_OCI from PECL..."

    # For PHP 8.4+, PDO_OCI is only available via PECL
    printf "instantclient,/opt/oracle/instantclient_21_13\n" | pecl install pdo_oci || {
        echo "Warning: PDO_OCI installation via PECL failed, trying alternative method..."

        # Fallback: try with specific version
        printf "instantclient,/opt/oracle/instantclient_21_13\n" | pecl install pdo_oci-1.1.0 || {
            echo "Error: PDO_OCI installation failed completely"
            exit 1
        }
    }
else
    echo "PHP < 8.4 detected, trying PHP source method..."

    # For older PHP versions, try downloading from PHP source
    wget -q "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" || {
        echo "Error: Could not download PHP source"
        exit 1
    }

    tar xzf "php-${PHP_VERSION}.tar.gz"

    if [ -d "php-${PHP_VERSION}/ext/pdo_oci/" ]; then
        cd "php-${PHP_VERSION}/ext/pdo_oci/"

        # Build PDO_OCI extension
        phpize
        ./configure --with-pdo-oci=instantclient,/opt/oracle/instantclient_21_13,21.13
        make
        make install
    else
        echo "PDO_OCI not found in PHP source, trying PECL..."
        cd /tmp
        printf "instantclient,/opt/oracle/instantclient_21_13\n" | pecl install pdo_oci
    fi

    # Clean up
    cd /tmp
    rm -rf "php-${PHP_VERSION}" "php-${PHP_VERSION}.tar.gz"
fi

# Clean up
cd /
rm -rf /tmp/pdo_oci* /tmp/PDO_OCI* /tmp/pear*

echo "Oracle Instant Client installation completed!"
echo "Installed extensions: oci8, pdo_oci"
echo "Note: Extensions will be enabled in the Dockerfile"
