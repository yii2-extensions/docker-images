#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Yii2 Docker - Debian Trixie${NC}"
echo -e "Build Type: ${YELLOW}${BUILD_TYPE}${NC}"
echo -e "PHP Version: ${YELLOW}${PHP_VERSION}${NC}"

# Function to wait for a service
wait_for_service() {
    local host=$1
    local port=$2
    local service=$3
    local max_tries=30
    local try=0

    echo -e "${YELLOW}Waiting for ${service}...${NC}"

    if command -v nc >/dev/null 2>&1; then
      while ! nc -z -w 2 "$host" "$port" 2>/dev/null; do
        try=$((try + 1))
        if [ $try -gt $max_tries ]; then
            echo -e "${RED}${service} failed to start at ${host}:${port}${NC}"
            return 1
        fi
        sleep 2
      done
    else
      # Fallback using bash's /dev/tcp
      while ! (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; do
        try=$((try + 1))
        if [ $try -gt $max_tries ]; then
            echo -e "${RED}${service} failed to start at ${host}:${port}${NC}"
            return 1
        fi
        sleep 2
      done
    fi

    echo -e "${GREEN}${service} is ready${NC}"
    return 0
}

# Set document root if provided
if [ -n "$APACHE_DOCUMENT_ROOT" ]; then
    sed -i "s|DocumentRoot.*|DocumentRoot ${APACHE_DOCUMENT_ROOT}|g" /etc/apache2/sites-available/yii2.conf
    sed -i "s|<Directory /var/www/app/web>|<Directory ${APACHE_DOCUMENT_ROOT}>|g" /etc/apache2/sites-available/yii2.conf
fi

# Set server name if provided
if [ -n "$APACHE_SERVER_NAME" ]; then
    echo "ServerName ${APACHE_SERVER_NAME}" >> /etc/apache2/apache2.conf
fi

# Configure Xdebug for development/full builds
# Set default Xdebug state based on build type
if [ "$BUILD_TYPE" = "full" ] && [ -z "$XDEBUG_ENABLED" ]; then
    XDEBUG_ENABLED="true"
fi

if [ "$BUILD_TYPE" = "dev" ] || [ "$BUILD_TYPE" = "full" ]; then
    if [ "$XDEBUG_ENABLED" = "true" ]; then
        echo -e "${YELLOW}Enabling Xdebug...${NC}"
        phpenmod xdebug

        # Update Xdebug settings if provided
        if [ -n "$XDEBUG_HOST" ]; then
            sed -i "s/xdebug.client_host.*/xdebug.client_host = ${XDEBUG_HOST}/g" /etc/php/${PHP_VERSION}/mods-available/xdebug.ini
        fi
        if [ -n "$XDEBUG_PORT" ]; then
            sed -i "s/xdebug.client_port.*/xdebug.client_port = ${XDEBUG_PORT}/g" /etc/php/${PHP_VERSION}/mods-available/xdebug.ini
        fi
        if [ -n "$XDEBUG_MODE" ]; then
            sed -i "s/xdebug.mode.*/xdebug.mode = ${XDEBUG_MODE}/g" /etc/php/${PHP_VERSION}/mods-available/xdebug.ini
        fi
    else
        echo -e "${YELLOW}Disabling Xdebug...${NC}"
        phpdismod xdebug 2>/dev/null || true
    fi
fi

# Update PHP memory limit if provided
if [ -n "$PHP_MEMORY_LIMIT" ]; then
    for sapi in apache2 cli; do
      ini="/etc/php/${PHP_VERSION}/${sapi}/conf.d/99-yii2.ini"
      [ -f "$ini" ] || echo "; yii2 overrides" > "$ini"
      grep -q '^memory_limit' "$ini" && \
        sed -i "s|^memory_limit.*|memory_limit = ${PHP_MEMORY_LIMIT}|" "$ini" || \
        echo "memory_limit = ${PHP_MEMORY_LIMIT}" >> "$ini"
    done
fi

# Create necessary directories
mkdir -p /var/www/app/{runtime,web/assets} 2>/dev/null || true
chown -R www-data:www-data /var/www/app/{runtime,web/assets} 2>/dev/null || true

# Copy requirements checker if it doesn't exist in web directory
if [ ! -d "/var/www/app/web/requirements" ] && [ -d "/opt/requirements-template" ]; then
    echo -e "${YELLOW}Installing requirements checker to web directory...${NC}"
    cp -r /opt/requirements-template /var/www/app/web/requirements
    chown -R www-data:www-data /var/www/app/web/requirements
    echo -e "${GREEN}Requirements checker installed successfully${NC}"
fi

# Install composer dependencies if composer.json exists and vendor doesn't
export COMPOSER_HOME=/var/www/.composer
mkdir -p "$COMPOSER_HOME"
chown -R www-data:www-data "$COMPOSER_HOME"

run_as_www_data() {
    if command -v runuser >/dev/null 2>&1; then
    runuser -u www-data -- "$@"
    else
    su -s /bin/sh -c "$*" www-data
    fi
}

if [ -f "/var/www/app/composer.json" ] && [ ! -d "/var/www/app/vendor" ]; then
    echo -e "${YELLOW}Installing Composer dependencies...${NC}"
    cd /var/www/app

    # Set composer home for www-data
    export COMPOSER_HOME=/var/www/.composer

    if [ "$YII_ENV" = "prod" ] || [ "$BUILD_TYPE" = "prod" ]; then
        echo -e "${YELLOW}Installing production dependencies (--no-dev)${NC}"
        run_as_www_data composer install \
            --no-dev \
            --no-interaction \
            --no-progress \
            --no-scripts \
            --optimize-autoloader
    else
        echo -e "${YELLOW}Installing all dependencies${NC}"
        run_as_www_data composer install \
            --no-interaction \
            --no-progress \
            --optimize-autoloader
    fi

    # Run post-install scripts
    if [ -f "yii" ]; then
        chmod +x yii
    fi

    echo -e "${GREEN}Dependencies installed successfully${NC}"
fi

# Wait for database services if in test mode
if [ "$BUILD_TYPE" = "full" ] || [ "$YII_ENV" = "test" ]; then
    # Wait for MySQL
    if [ -n "$DB_MYSQL_HOST" ]; then
        wait_for_service "$DB_MYSQL_HOST" 3306 "MySQL"
    fi

    # Wait for PostgreSQL
    if [ -n "$DB_PGSQL_HOST" ]; then
        wait_for_service "$DB_PGSQL_HOST" 5432 "PostgreSQL"
    fi

    # Wait for Redis
    if [ -n "$DB_REDIS_HOST" ]; then
        wait_for_service "$DB_REDIS_HOST" 6379 "Redis"
    fi

    # Wait for MSSQL
    if [ -n "$DB_MSSQL_HOST" ]; then
        wait_for_service "$DB_MSSQL_HOST" 1433 "SQL Server"
    fi

    # Wait for Oracle
    if [ -n "$DB_ORACLE_HOST" ]; then
        wait_for_service "$DB_ORACLE_HOST" 1521 "Oracle"
    fi
fi

# Run database migrations if enabled
if [ -f "/var/www/app/yii" ] && [ "$YII_ENV" != "test" ] && [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    echo -e "${YELLOW}Running database migrations...${NC}"
    cd /var/www/app
    run_as_www_data php yii migrate --interactive=0 || {
      echo -e "${RED}Migrations failed${NC}"; exit 1;
    }
fi

# Create health check endpoint
if [ "${ENABLE_HEALTH_ENDPOINT:-false}" = "true" ]; then
cat > /var/www/app/web/health.php << 'EOF'
<?php
header('Content-Type: application/json');
$health = [
    'status' => 'healthy',
    'timestamp' => date('c'),
    'php_version' => PHP_VERSION,
    'build_type' => getenv('BUILD_TYPE') ?: 'unknown',
    'environment' => getenv('YII_ENV') ?: 'unknown'
];

// Check Apache
$health['services']['apache'] = 'running';

// Check PHP extensions
$health['extensions'] = [
    'opcache' => extension_loaded('opcache'),
    'pdo' => extension_loaded('pdo'),
    'redis' => extension_loaded('redis'),
    'xdebug' => extension_loaded('xdebug'),
];

// Check database connections if in test mode
if (getenv('BUILD_TYPE') === 'full') {
    $health['extensions']['oci8'] = extension_loaded('oci8');
    $health['extensions']['sqlsrv'] = extension_loaded('sqlsrv');
}

// Check if requirements checker is available
$health['features'] = [
    'requirements_checker' => file_exists('/var/www/app/web/requirements/index.php')
];

http_response_code(200);
echo json_encode($health, JSON_PRETTY_PRINT);
EOF

chown www-data:www-data /var/www/app/web/health.php 2>/dev/null || true
fi

echo -e "${GREEN}Container initialization complete${NC}"

# Execute the main command
exec "$@"
