#==============================================================================
# Yii2 Docker - Debian Trixie + PHP 8.4 FPM + Apache with HTTP/2
# Supports: full (testing), dev (development), prod (production)
#==============================================================================

ARG BUILD_TYPE=dev
ARG PHP_VERSION=8.4

#==============================================================================
# Base System
#==============================================================================
FROM php:${PHP_VERSION}-fpm-trixie AS base

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    # Apache Configuration
    APACHE_ACCESS_LOG=/proc/self/fd/1 \
    APACHE_DOCUMENT_ROOT=/var/www/app/web \
    APACHE_ERROR_LOG_FILE=/proc/self/fd/2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_RUN_GROUP=www-data \
    APACHE_RUN_USER=www-data \
    APACHE_SSL_ENABLED=true \
    # GD configuration
    IPE_GD_WITHOUTAVIF=1 \
    # PHP Core Configuration
    PHP_MAX_EXECUTION_TIME=30 \
    PHP_MAX_FILE_UPLOADS=20 \
    PHP_MAX_INPUT_TIME=60 \
    PHP_MAX_INPUT_VARS=1000 \
    PHP_MEMORY_LIMIT=256M \
    PHP_POST_MAX_SIZE=50M \
    PHP_UPLOAD_MAX_FILESIZE=50M \
    # PHP Error Configuration
    PHP_DISPLAY_ERRORS=off \
    PHP_DISPLAY_STARTUP_ERRORS=off \
    PHP_ERROR_LOG=/proc/self/fd/2 \
    PHP_ERROR_REPORTING="E_ALL & ~E_DEPRECATED" \
    PHP_EXPOSE=off \
    PHP_LOG_ERRORS=on \
    # PHP Security Configuration
    PHP_ALLOW_URL_FOPEN=off \
    PHP_ALLOW_URL_INCLUDE=off \
    PHP_DATE_TIMEZONE=UTC \
    PHP_DISABLE_FUNCTIONS=exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source \
    # PHP Session Configuration
    PHP_SESSION_HANDLER=files \
    PHP_SESSION_PATH=/var/lib/php/sessions \
    # PHP-FPM Configuration
    PHP_FPM_ACCESS_LOG=/proc/self/fd/1 \
    PHP_FPM_CATCH_OUTPUT=yes \
    PHP_FPM_IDLE_TIMEOUT=10s \
    PHP_FPM_LOG_LEVEL=warning \
    PHP_FPM_MAX_CHILDREN=50 \
    PHP_FPM_MAX_REQUESTS=500 \
    PHP_FPM_MAX_SPARE=35 \
    PHP_FPM_MIN_SPARE=5 \
    PHP_FPM_PING_PATH=/fpm-ping \
    PHP_FPM_PM=dynamic \
    PHP_FPM_REQUEST_TIMEOUT=30 \
    PHP_FPM_RLIMIT_FILES=131072 \
    PHP_FPM_SLOWLOG_TIMEOUT=5s \
    PHP_FPM_START_SERVERS=5 \
    PHP_FPM_STATUS_PATH=/fpm-status \
    # SSL Configuration
    SSL_AUTO_GENERATE=true

# Layer 1: System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    supervisor \
    curl \
    openssl \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: Install php-extension-installer tool
ADD --chmod=0755 \
    https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    /usr/local/bin/

# Layer 3: Core PHP extensions for Yii2
RUN install-php-extensions \
    apcu \
    bcmath \
    intl \
    opcache \
    pcntl \
    zip \
    imagick \
    gd \
    @composer \
    --cleanup

# Layer 4: Database extensions
RUN install-php-extensions \
    pdo_mysql \
    pdo_pgsql \
    redis \
    --cleanup

# Layer 5: Apache configuration
RUN a2dismod mpm_prefork 2>/dev/null || true \
    && a2enmod mpm_event \
    && a2enmod rewrite headers expires ssl proxy proxy_fcgi http2 \
    && a2dissite 000-default

# Layer 6: Create directories and set permissions
RUN mkdir -p \
    ${APACHE_LOCK_DIR} \
    /etc/apache2/ssl \
    /etc/apache2/ssl/external \
    /var/cache/apache2 \
    /var/lib/php/sessions \
    /var/lib/php/tmp \
    /var/run/apache2 \
    /var/run/php \
    && chown -R www-data:www-data \
    /etc/apache2/ssl \
    /var/cache/apache2 \
    /var/lib/php \
    /var/run/apache2 \
    /var/run/php \
    && chmod 755 /etc/apache2/ssl /var/cache/apache2 /etc/apache2/ssl/external

# Layer 7: Configure sudo for www-data
RUN echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/www-data \
    && chmod 0440 /etc/sudoers.d/www-data

#==============================================================================
# Development Build
#==============================================================================
FROM base AS dev

# Layer 8: Development-only extensions
RUN install-php-extensions \
    xdebug \
    --cleanup

# Layer 9: Additional database extensions for development
RUN install-php-extensions \
    mongodb \
    memcached \
    --cleanup

# Layer 10: Development utilities
RUN install-php-extensions \
    soap \
    yaml \
    --cleanup

# Layer 11: Development tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    vim \
    default-mysql-client \
    postgresql-client \
    redis-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

#==============================================================================
# Full Testing Build
#==============================================================================
FROM dev AS full

# Layer 12: Oracle extensions
RUN install-php-extensions \
    oci8 \
    pdo_oci \
    --cleanup

# Layer 13: Additional testing extensions
RUN install-php-extensions \
    tidy \
    --cleanup

# Layer 14: Microsoft SQL Server support
# Note: Using Debian 12 (bookworm) repo since Trixie (13) is not yet officially supported by Microsoft
RUN set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        ca-certificates \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
    && apt-get install -y unixodbc-dev \
    && install-php-extensions sqlsrv pdo_sqlsrv --cleanup \
    && apt-get purge -y --auto-remove gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#==============================================================================
# Production Build
#==============================================================================
FROM base AS prod

# Production build already has all necessary extensions from base
RUN apt-get purge -y --auto-remove git 2>/dev/null || true \
    && rm -rf /var/www/html/*

#==============================================================================
# Final Stage
#==============================================================================
FROM ${BUILD_TYPE} AS final

ARG BUILD_TYPE
ENV BUILD_TYPE=${BUILD_TYPE} \
    SERVICE_TYPE=apache-fpm

# Copy Apache configuration files
COPY src/flavor/apache/etc/apache2.conf /etc/apache2/
COPY src/flavor/apache/etc/conf-available/ /etc/apache2/conf-available/
COPY src/flavor/apache/etc/sites-available/ /etc/apache2/sites-available/
COPY src/flavor/apache/etc/ssl/ /etc/apache2/ssl/

# Copy PHP Configurations
COPY src/php-fpm/docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY src/php/ /tmp/php/
RUN cp "/tmp/php/${BUILD_TYPE}.ini" /usr/local/etc/php/conf.d/99-app.ini \
    && rm -rf /tmp/php

# Copy Supervisor configurations
COPY src/supervisor/conf.d/ /etc/supervisor/conf.d/
COPY src/supervisor/supervisord.conf /etc/supervisor/

# Copy scripts
COPY src/script/common/ /usr/local/bin/common/
COPY src/script/entrypoint.sh /usr/local/bin/entrypoint

# Enable only security configuration
# Site selection will be done dynamically by 30-ssl.sh script
RUN a2enconf security php-fpm-proxy \
    && a2dissite 000-default 2>/dev/null || true

# Make scripts executable
RUN chmod +x /usr/local/bin/entrypoint

WORKDIR /var/www/app

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -fsS -A healthcheck http://localhost/health || curl -fsS -A healthcheck http://localhost/fpm-ping || exit 1

ENTRYPOINT ["entrypoint"]
