#==============================================================================
# Yii2 Docker - Debian Trixie + PHP 8.5 FPM + Apache with HTTP/2
# Supports: full (testing), dev (development), prod (production)
#==============================================================================

ARG BUILD_TYPE=dev
ARG PHP_VERSION=8.5

#------------------------------------------------------------------------------
# Base System
#------------------------------------------------------------------------------
FROM php:${PHP_VERSION}-fpm-trixie AS base

# Set shell options for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    # Apache Configuration
    APACHE_DOCUMENT_ROOT=/var/www/app/web \
    APACHE_ERROR_LOG_FILE=/proc/self/fd/2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_RUN_GROUP=www-data \
    APACHE_RUN_USER=www-data \
    # Apache MPM Event Configuration
    APACHE_ASYNC_REQUEST_WORKER_FACTOR=2 \
    APACHE_GRACEFUL_SHUTDOWN_TIMEOUT=10 \
    APACHE_SERVER_LIMIT=32 \
    APACHE_MAX_CONNECTIONS_PER_CHILD=5000 \
    APACHE_MAX_REQUEST_WORKERS=800 \
    APACHE_MAX_SPARE_THREADS=100 \
    APACHE_MIN_SPARE_THREADS=25 \
    APACHE_START_SERVERS=4 \
    APACHE_THREAD_LIMIT=64 \
    APACHE_THREADS_PER_CHILD=25 \
    APACHE_LISTEN_BACKLOG=511 \
    # Composer Configuration
    COMPOSER_HOME=/var/www/.composer \
    # Apache Logging Configuration
    APACHE_ACCESS_LOG=/proc/self/fd/1 \
    # Apache optional: Enable HTTP to HTTPS redirect
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
    PHP_DISPLAY_ERRORS=0 \
    PHP_DISPLAY_STARTUP_ERRORS=0 \
    PHP_ERROR_LOG=/proc/self/fd/2 \
    PHP_ERROR_REPORTING="E_ALL & ~E_DEPRECATED" \
    PHP_EXPOSE=0 \
    PHP_LOG_ERRORS=1 \
    # PHP Security Configuration
    PHP_ALLOW_URL_FOPEN=0 \
    PHP_ALLOW_URL_INCLUDE=0 \
    PHP_DATE_TIMEZONE="UTC" \
    PHP_DISABLE_FUNCTIONS="exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source" \
    # PHP Session Configuration
    PHP_SESSION_HANDLER=files \
    PHP_SESSION_PATH=/var/lib/php/sessions \
    # PHP-FPM Configuration
    PHP_FPM_ACCESS_LOG=/proc/self/fd/1 \
    PHP_FPM_CATCH_OUTPUT=yes \
    PHP_FPM_IDLE_TIMEOUT="10s" \
    PHP_FPM_LOG_LEVEL=warning \
    PHP_FPM_MAX_CHILDREN=50 \
    PHP_FPM_MAX_REQUESTS=500 \
    PHP_FPM_MAX_SPARE=35 \
    PHP_FPM_MIN_SPARE=5 \
    PHP_FPM_PING_PATH=/fpm-ping \
    PHP_FPM_PM=dynamic \
    PHP_FPM_REQUEST_TIMEOUT=30 \
    PHP_FPM_RLIMIT_FILES=131072 \
    PHP_FPM_SLOWLOG_TIMEOUT="5s" \
    PHP_FPM_START_SERVERS=5 \
    PHP_FPM_STATUS_PATH=/fpm-status \
    # SSL Configuration
    SSL_AUTO_GENERATE=true

# Layer 01: System packages + gosu
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    brotli \
    supervisor \
    curl \
    openssl \
    sudo \
    gosu \
    vim-tiny \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Layer 02: Install php-extension-installer tool
ADD --chmod=0755 \
    https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    /usr/local/bin/

# Layer 03: Base extensions
RUN install-php-extensions \
    @composer \
    apcu \
    bcmath \
    gd \
    imagick \
    intl \
    opcache \
    pcntl \
    pdo_mysql \
    pdo_pgsql \
    redis \
    zip

# Layer 04: Create directories and set permissions
RUN mkdir -p \
    ${APACHE_LOCK_DIR} \
    /etc/apache2/ssl \
    /var/cache/apache2 \
    /var/lib/php/sessions \
    /var/lib/php/tmp \
    /var/run/apache2 \
    /var/run/php \
    /var/www/.cache/node \
    /var/www/.composer \
    /var/www/.composer/cache \
    /var/www/.npm \
    && chown -R www-data:www-data \
    /etc/apache2/ssl \
    /var/cache/apache2 \
    /var/lib/php \
    /var/run/apache2 \
    /var/run/php \
    /var/www/.cache/node \
    /var/www/.composer \
    /var/www/.composer/cache \
    /var/www/.npm \
    && chmod 750 /etc/apache2/ssl \
    && chmod 755 /var/cache/apache2

# Layer 05: Configure sudo for www-data
RUN echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/www-data \
    && chmod 0440 /etc/sudoers.d/www-data

#------------------------------------------------------------------------------
# Development Build
#------------------------------------------------------------------------------
FROM base AS dev

# Layer 06: Development extensions
RUN install-php-extensions \
    memcached \
    mongodb \
    soap \
    xdebug \
    yaml

#------------------------------------------------------------------------------
# Full Testing Build
#------------------------------------------------------------------------------
FROM dev AS full

# Layer 07: Full extensions
RUN install-php-extensions \
    oci8 \
    pdo_oci \
    tidy

# Layer 08: Microsoft SQL Server support
# Note: Using Debian 12 (bookworm) repo since Trixie (13) is not yet officially supported by Microsoft
RUN /bin/bash -o pipefail -c "set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        ca-certificates \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo \"deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main\" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && apt-get install -y --no-install-recommends unixodbc unixodbc-dev $PHPIZE_DEPS \
    && printf "\\n" | pecl install sqlsrv-5.12.0 \
    && if [[ "$(php -r 'echo PHP_VERSION_ID;')" -ge 80500 ]]; then \
        cd /tmp \
        && pecl download pdo_sqlsrv-5.12.0 \
        && tar -xf pdo_sqlsrv-5.12.0.tgz \
        && rm -f pdo_sqlsrv-5.12.0.tgz \
        && cd pdo_sqlsrv-5.12.0 \
        && sed -i 's/= dbh->error_mode/= (enum pdo_error_mode) dbh->error_mode/' pdo_dbh.cpp \
        && sed -i 's/zval_ptr_dtor( &dbh->query_stmt_zval );/OBJ_RELEASE(dbh->query_stmt_obj);dbh->query_stmt_obj=NULL;/' php_pdo_sqlsrv_int.h \
        && phpize \
        && ./configure --with-php-config="$(command -v php-config)" \
        && make -j"$(nproc)" \
        && make install \
        && rm -rf /tmp/pdo_sqlsrv-5.12.0; \
    else \
        printf "\\n" | pecl install pdo_sqlsrv-5.12.0; \
    fi \
    && docker-php-ext-enable sqlsrv pdo_sqlsrv \
    && apt-get purge -y --auto-remove gnupg unixodbc-dev $PHPIZE_DEPS \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"

#==============================================================================
# Production Build
#==============================================================================
FROM base AS prod

# Layer 09: Production build already has all necessary extensions from base
RUN apt-get purge -y --auto-remove git 2>/dev/null || true \
    && rm -rf /var/www/html/*

#==============================================================================
# Final Stage
#==============================================================================
FROM ${BUILD_TYPE} AS final

ARG BUILD_TYPE
ENV BUILD_TYPE=${BUILD_TYPE} \
    SERVICE_TYPE=apache-fpm

# Layer 10: Copy Apache configuration files
COPY src/etc/apache2/ /etc/apache2/

# Layer 11: Copy PHP Configurations
COPY src/etc/php-fpm.d/ /usr/local/etc/php-fpm.d/
COPY src/etc/php/${BUILD_TYPE}.ini /usr/local/etc/php/conf.d/99-app.ini

# Layer 12: Copy Supervisor configurations
COPY src/supervisor/conf.d/ /etc/supervisor/conf.d/
COPY src/supervisor/supervisord.conf /etc/supervisor/

# Layer 13: Copy scripts
COPY src/script/common/ /usr/local/bin/common/
COPY --chmod=0755 src/script/entrypoint.sh /usr/local/bin/entrypoint

# Layer 14: Apache configuration
RUN a2dismod mpm_prefork 2>/dev/null || true \
    && a2enmod brotli \
    && a2enmod mpm_event \
    && a2enmod filter rewrite headers expires ssl proxy proxy_fcgi http2 \
    && a2dissite 000-default

# Layer 15: Enable Apache configurations
RUN a2enconf \
    01-performance.conf \
    02-security.conf \
    03-ssl-tls.conf \
    04-compression.conf \
    05-php-fpm.conf \
    06-logging.conf \
    07-rate-limiting.conf

# Image metadata labels
LABEL apache.version="2.4" \
    build.type="${BUILD_TYPE}" \
    debian.version="trixie" \
    maintainer="yii2-extensions" \
    php.version="${PHP_VERSION}" \
    org.opencontainers.image.authors="@terabytesoftw" \
    org.opencontainers.image.base.name="php:${PHP_VERSION}-fpm-trixie" \
    org.opencontainers.image.description="Debian Trixie + PHP ${PHP_VERSION} FPM + Apache with HTTP/2 support for Yii2 applications. Build type: ${BUILD_TYPE}" \
    org.opencontainers.image.documentation="https://github.com/yii2-extensions/docker-images#readme" \
    org.opencontainers.image.licenses="BSD-3-Clause" \
    org.opencontainers.image.title="Yii2 Apache Docker Image" \
    org.opencontainers.image.vendor="yii2-extensions"

WORKDIR /var/www/app

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -fsS -A healthcheck http://localhost/health || curl -fsS -A healthcheck http://localhost/fpm-ping || exit 1

ENTRYPOINT ["entrypoint"]
