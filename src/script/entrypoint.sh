#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Yii2 Docker - Debian Trixie${NC}"
echo -e "Build Type: ${YELLOW}${BUILD_TYPE}${NC}"
echo -e "PHP Version: ${YELLOW}${PHP_VERSION}${NC}"

# Log current user
CURRENT_USER=$(whoami)
echo -e "${BLUE}Running as user: ${YELLOW}${CURRENT_USER}${NC}"
echo -e "${BLUE}Apache/PHP logs will be sent to STDOUT/STDERR for Docker observability${NC}"

# Signal handling for graceful shutdown
trap_signals() {
    echo -e "${YELLOW}Received shutdown signal, gracefully stopping Apache...${NC}"
    apache2ctl stop
    exit 0
}

# Trap signals for graceful shutdown
trap trap_signals SIGTERM SIGINT

# Function to update or append configuration in a file
update_or_append_config() {
    local key="$1"
    local value="$2"
    local file="$3"

    # Check if the key exists in the config file
    if grep -q "^${key} =" "$file"; then
        # Update the existing key with the new value
        sed -i "s|^${key} =.*|${key} = ${value}|" "$file"
    else
        # Append the key-value pair to the file
        echo "${key} = ${value}" >> "$file"
    fi
}

# Function to run commands as www-data with proper signal handling
run_as_www_data() {
    if [ "$(id -u)" = "0" ]; then
        exec gosu www-data "$@"
    else
        # If already www-data, run directly
        exec "$@"
    fi
}

# Only run initialization steps if we're root
if [ "$(id -u)" = "0" ]; then
    echo -e "${YELLOW}Running initialization as root...${NC}"

    # Environment setup
    export APACHE_RUN_USER=${APACHE_RUN_USER:-www-data}
    export APACHE_RUN_GROUP=${APACHE_RUN_GROUP:-www-data}
    export APACHE_LOG_DIR=${APACHE_LOG_DIR:-/var/log/apache2}
    export APACHE_LOCK_DIR=${APACHE_LOCK_DIR:-/var/lock/apache2}
    export APACHE_PID_FILE=${APACHE_PID_FILE:-/var/run/apache2/apache2.pid}
    export APACHE_RUN_DIR=${APACHE_RUN_DIR:-/var/run/apache2}

    # Ensure Apache run directory exists and has correct permissions
    mkdir -p ${APACHE_RUN_DIR} ${APACHE_LOG_DIR} ${APACHE_LOCK_DIR}
    chown ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} ${APACHE_RUN_DIR} ${APACHE_LOG_DIR} ${APACHE_LOCK_DIR}

    # Set document root if provided
    if [ -n "$APACHE_DOCUMENT_ROOT" ]; then
        echo -e "${YELLOW}Setting Apache document root to: ${APACHE_DOCUMENT_ROOT}${NC}"
        sed -i "s|DocumentRoot.*|DocumentRoot ${APACHE_DOCUMENT_ROOT}|g" /etc/apache2/sites-available/yii2.conf
        sed -i "s|<Directory /var/www/app/web>|<Directory ${APACHE_DOCUMENT_ROOT}>|g" /etc/apache2/sites-available/yii2.conf
    fi

    # Set server name if provided to suppress warning
    if [ -n "$APACHE_SERVER_NAME" ]; then
        echo -e "${YELLOW}Setting Apache ServerName to: ${APACHE_SERVER_NAME}${NC}"
        update_or_append_config "ServerName" "${APACHE_SERVER_NAME}" "/etc/apache2/apache2.conf"
    else
        # Set a default ServerName to suppress warnings
        echo -e "${YELLOW}Setting default Apache ServerName to suppress warnings${NC}"
        update_or_append_config "ServerName" "localhost" "/etc/apache2/apache2.conf"
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
          update_or_append_config "memory_limit" "$PHP_MEMORY_LIMIT" "$ini"
        done
    fi

    # Apply additional PHP configurations from environment variables
    if [ -n "$PHP_MAX_EXECUTION_TIME" ]; then
        update_or_append_config "max_execution_time" "$PHP_MAX_EXECUTION_TIME" "/etc/php/${PHP_VERSION}/apache2/conf.d/99-yii2.ini"
    fi
    if [ -n "$PHP_POST_MAX_SIZE" ]; then
        update_or_append_config "post_max_size" "$PHP_POST_MAX_SIZE" "/etc/php/${PHP_VERSION}/apache2/conf.d/99-yii2.ini"
    fi
    if [ -n "$PHP_UPLOAD_MAX_FILESIZE" ]; then
        update_or_append_config "upload_max_filesize" "$PHP_UPLOAD_MAX_FILESIZE" "/etc/php/${PHP_VERSION}/apache2/conf.d/99-yii2.ini"
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

    if [ -f "/var/www/app/composer.json" ] && [ ! -d "/var/www/app/vendor" ]; then
        echo -e "${YELLOW}Installing Composer dependencies...${NC}"
        cd /var/www/app

        # Set composer home for www-data
        export COMPOSER_HOME=/var/www/.composer

        if [ "$YII_ENV" = "prod" ] || [ "$BUILD_TYPE" = "prod" ]; then
            echo -e "${YELLOW}Installing production dependencies (--no-dev)${NC}"
            gosu www-data composer install \
                --no-dev \
                --no-interaction \
                --no-progress \
                --no-scripts \
                --optimize-autoloader
        else
            echo -e "${YELLOW}Installing all dependencies${NC}"
            gosu www-data composer install \
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
        gosu www-data php yii migrate --interactive=0 || {
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

    # Final verification of Apache configuration
    echo -e "${YELLOW}Verifying Apache configuration...${NC}"

    # Check Apache configuration
    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        echo -e "${GREEN}Apache configuration is valid${NC}"
    else
        echo -e "${RED}Apache configuration test failed!${NC}"
        apache2ctl configtest
        exit 1
    fi

    echo -e "${GREEN}Container initialization complete${NC}"
    echo -e "${BLUE}Switching to www-data user and starting Apache...${NC}"

    # Switch to www-data and execute the main command
    run_as_www_data "$@"
else
    echo -e "${BLUE}Already running as non-root user (${CURRENT_USER})${NC}"
    echo -e "${BLUE}Starting Apache in foreground mode...${NC}"

    # Execute the main command directly
    exec "$@"
fi
