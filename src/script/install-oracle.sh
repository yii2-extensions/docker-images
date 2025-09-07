#!/bin/bash
set -euo pipefail

# Oracle Instant Client Installation Script
# Version: 21.x (Latest LTS)

echo "Installing Oracle Instant Client and PHP extensions..."

# Function to install packages with cleanup
install_packages() {
    apt-get update && apt-get install -y --no-install-recommends "$@" \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*
}

# Function to install PECL extension with fallback
install_oracle_extension() {
    local extension="$1"
    local fallback_version="$2"
    
    echo "Installing PHP $extension extension..."
    printf "instantclient,/opt/oracle/instantclient_21_13\n" | pecl install "$extension" || {
        echo "Warning: $extension installation failed, trying version $fallback_version..."
        printf "instantclient,/opt/oracle/instantclient_21_13\n" | pecl install "$extension-$fallback_version"
    }
}

# Install dependencies
install_packages libaio1t64 wget unzip

# Oracle setup
ORACLE_VERSION=21.13.0.0.0
ORACLE_BASE_URL=https://download.oracle.com/otn_software/linux/instantclient/2113000
ORACLE_HOME=/opt/oracle/instantclient_21_13

# Download and install Oracle Instant Client
mkdir -p /opt/oracle && cd /opt/oracle
echo "Downloading Oracle Instant Client ${ORACLE_VERSION}..."
wget -q ${ORACLE_BASE_URL}/instantclient-basic-linux.x64-${ORACLE_VERSION}dbru.zip
wget -q ${ORACLE_BASE_URL}/instantclient-sdk-linux.x64-${ORACLE_VERSION}dbru.zip

# Extract and setup
unzip -q instantclient-basic-linux.x64-${ORACLE_VERSION}dbru.zip
unzip -q instantclient-sdk-linux.x64-${ORACLE_VERSION}dbru.zip
rm -f *.zip

# Create symbolic links and configure library path
cd "$ORACLE_HOME"
ln -sf libclntsh.so.21.1 libclntsh.so
ln -sf libocci.so.21.1 libocci.so
echo "$ORACLE_HOME" > /etc/ld.so.conf.d/oracle-instantclient.conf
ldconfig

# Set environment variables
export ORACLE_HOME LD_LIBRARY_PATH="$ORACLE_HOME:${LD_LIBRARY_PATH:-}"

# Install PHP extensions
echo "Installing PHP Oracle extensions..."
pecl channel-update pecl.php.net

# Install OCI8
install_oracle_extension "oci8" "3.4.0"

# Install PDO_OCI (version-dependent installation)
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION.'.'.PHP_RELEASE_VERSION;")
PHP_MAJOR=$(php -r "echo PHP_MAJOR_VERSION;")
PHP_MINOR=$(php -r "echo PHP_MINOR_VERSION;")

echo "Detected PHP version: $PHP_VERSION"

if { [ "$PHP_MAJOR" -gt 8 ] ; } || { [ "$PHP_MAJOR" -eq 8 ] && [ "$PHP_MINOR" -ge 4 ] ; }; then
    echo "PHP 8.4+ detected, installing PDO_OCI from PECL..."
    install_oracle_extension "pdo_oci" "1.1.0"
else
    echo "PHP < 8.4 detected, trying PHP source method..."
    cd /tmp
    wget -q "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" || {
        echo "Could not download PHP source, trying PECL..."
        install_oracle_extension "pdo_oci" "1.1.0"
        cd / && rm -rf /tmp/pdo_oci* /tmp/PDO_OCI* /tmp/pear*
        echo "Oracle Instant Client installation completed!"
        exit 0
    }

    tar xzf "php-${PHP_VERSION}.tar.gz"
    if [ -d "php-${PHP_VERSION}/ext/pdo_oci/" ]; then
        cd "php-${PHP_VERSION}/ext/pdo_oci/"
        phpize
        ./configure --with-pdo-oci=instantclient,/opt/oracle/instantclient_21_13,21.13
        make && make install
    else
        echo "PDO_OCI not found in PHP source, using PECL..."
        cd /tmp
        install_oracle_extension "pdo_oci" "1.1.0"
    fi
fi

# Clean up
cd / && rm -rf /tmp/php-* /tmp/pdo_oci* /tmp/PDO_OCI* /tmp/pear*

echo "Oracle Instant Client installation completed!"
echo "Note: Extensions will be enabled in the Dockerfile"
