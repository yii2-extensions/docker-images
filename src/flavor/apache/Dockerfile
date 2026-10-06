# syntax=docker/dockerfile:1.7
#==============================================================================
# Yii2 Docker - Debian Trixie + PHP FPM + Apache with HTTP/2
# Supports: full (testing), dev (development), prod (production)
#
# Build flow:
#   ext-prod -> ext-dev -> ext-full   install system packages and PHP extensions
#   rootfs                            purge the toolchain and verify the result
#   image                             flatten rootfs into one layer, add the runtime configuration as small layers
#   smoke                             run tests/smoke.sh against the image
#   final                             default target, same as image
#==============================================================================

ARG BUILD_TYPE=dev
ARG PHP_VERSION=8.5

# Upstream tag prefix, differs from PHP_VERSION for release candidates (for example 8.6-rc)
ARG PHP_BASE_TAG=${PHP_VERSION}

# Extension lists, overridable per PHP version from docker-bake.hcl; the smoke stage asserts the same lists
ARG PHP_EXTENSIONS_PROD="@composer apcu bcmath gd imagick intl opcache pcntl pdo_mysql pdo_pgsql redis zip"
ARG PHP_EXTENSIONS_DEV="memcached mongodb soap xdebug yaml"
ARG PHP_EXTENSIONS_FULL="oci8 pdo_oci pdo_sqlsrv sqlsrv tidy"

#------------------------------------------------------------------------------
# Build Tools
#------------------------------------------------------------------------------
FROM mlocati/php-extension-installer:2.12.0 AS installer

FROM node:24-trixie-slim AS node

#------------------------------------------------------------------------------
# Production Extensions
#------------------------------------------------------------------------------
FROM php:${PHP_BASE_TAG}-fpm-trixie AS ext-prod

# Set shell options for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Build-time only settings, not persisted in the image environment
ARG DEBIAN_FRONTEND=noninteractive
ARG IPE_GD_WITHOUTAVIF=1

# Extension list, default declared before the first stage
ARG PHP_EXTENSIONS_PROD

# Layer 01: System packages (curl, openssl and ca-certificates are listed so the toolchain purge keeps them)
# The auto-installed package list is saved because the installer marks some of them, toolchain included, as manual
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    ca-certificates \
    curl \
    openssl \
    supervisor \
    && apt-mark showauto >/usr/src/apt-auto-packages.txt \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Layer 02: Install php-extension-installer tool
COPY --from=installer /usr/bin/install-php-extensions /usr/local/bin/

# Layer 03: Production extensions
# hadolint ignore=SC2086
RUN install-php-extensions ${PHP_EXTENSIONS_PROD}

#------------------------------------------------------------------------------
# Development Extensions
#------------------------------------------------------------------------------
FROM ext-prod AS ext-dev

ARG DEBIAN_FRONTEND=noninteractive
ARG PHP_EXTENSIONS_DEV

# Layer 04: Development extensions
# hadolint ignore=SC2086
RUN install-php-extensions ${PHP_EXTENSIONS_DEV}

# Layer 05: Node.js and npm for front-end assets
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

#------------------------------------------------------------------------------
# Full Testing Extensions
#------------------------------------------------------------------------------
FROM ext-dev AS ext-full

ARG DEBIAN_FRONTEND=noninteractive
ARG PHP_EXTENSIONS_FULL

# Layer 06: Full extensions (Oracle Instant Client and Microsoft ODBC Driver 18 are installed by the installer)
# hadolint ignore=SC2086
RUN install-php-extensions ${PHP_EXTENSIONS_FULL}

#==============================================================================
# Root Filesystem
#==============================================================================
FROM ext-${BUILD_TYPE} AS rootfs

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG BUILD_TYPE
ARG DEBIAN_FRONTEND=noninteractive

# Layer 07: Remove the compiler toolchain and PHP sources with the purge logic install-extensions ships, and record
# the upstream PHP source (its ENV is not carried into the image) so install-extensions can rebuild extensions later
# hadolint ignore=SC3010,SC3014
RUN --mount=type=bind,source=src/script/install-extensions.sh,target=/mnt/install-extensions <<'EOF'
#!/bin/bash
set -euo pipefail

[[ "${PHP_SHA256}" =~ ^[0-9a-f]{64}$ && -n "${PHP_URL}" && -n "${PHP_VERSION}" ]]
mkdir -p /usr/local/lib/yii2-docker
printf 'PHP_VERSION=%s\nPHP_URL=%s\nPHP_SHA256=%s\n' "${PHP_VERSION}" "${PHP_URL}" "${PHP_SHA256}" \
    >/usr/local/lib/yii2-docker/php-source.env

# Ghostscript with its fonts and data (about 22 MiB, PDF, PS and EPS support in imagick) is not shipped; the installer
# marks these packages manual, so they are purged by name and the toolchain purge auto-removes what only they needed
mapfile -t ghostscript < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' ghostscript 'libgs[0-9]*' libgs-common poppler-data \
        fonts-urw-base35 xfonts-utils xfonts-encodings 2>/dev/null | awk '/^ii/ { print $2 }'
)
if [[ ${#ghostscript[@]} -gt 0 ]]; then
    apt-get purge -y "${ghostscript[@]}"
fi

bash /mnt/install-extensions --purge /usr/src/apt-auto-packages.txt

if [[ "${BUILD_TYPE}" == "prod" ]]; then
    rm -f /usr/local/bin/phpdbg /usr/local/php/man/man1/phpdbg.1
    rm -rf /var/www/html/*
fi
EOF

# Layer 08: Integrity gate, fails the build when the purge broke a binary, an extension or PHP itself
# hadolint ignore=SC3010
RUN --mount=type=bind,source=src/script/install-extensions.sh,target=/mnt/install-extensions <<'EOF'
#!/bin/bash
set -euo pipefail

# Upstream environment that the image stage declares again by hand; fail on drift
read -r -a deps <<<"${PHPIZE_DEPS}"
[[ "${deps[*]}" == "autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c" ]]
[[ "${PHP_INI_DIR}" == "/usr/local/etc/php" ]]
[[ "${PHP_CFLAGS}" == "-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" ]]
[[ "${PHP_CPPFLAGS}" == "${PHP_CFLAGS}" ]]
[[ "${PHP_LDFLAGS}" == "-Wl,-O1 -pie" ]]

# Toolchain and sources gone, every ELF file resolves its libraries, PHP and PHP-FPM start cleanly
bash /mnt/install-extensions --verify

# Node.js tooling, when present, must run
if [[ -e /usr/local/bin/node ]]; then
    node --version
    npm --version
    npx --version
fi
EOF

#==============================================================================
# Image (flattened root filesystem, then small configuration layers and metadata)
#==============================================================================
FROM scratch AS image

ARG BUILD_TYPE
ARG PHP_BASE_TAG
ARG PHP_VERSION

# Layer 01: Root filesystem as one layer, rebuilt only when the base image, packages or extensions change
# hadolint ignore=DL3067
COPY --from=rootfs / /

# Upstream environment needed to run PHP and to build extensions (docker-php-ext-*, phpize, install-extensions)
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c" \
    PHP_INI_DIR=/usr/local/etc/php \
    PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" \
    PHP_CPPFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" \
    PHP_LDFLAGS="-Wl,-O1 -pie"

# Environment variables (declared before the configuration layers, apache2ctl configtest reads them)
ENV BUILD_TYPE=${BUILD_TYPE} \
    SERVICE_TYPE=apache-fpm \
    # Apache Configuration
    APACHE_DOCUMENT_ROOT=/var/www/app/web \
    APACHE_HTTP_PORT=80 \
    APACHE_HTTPS_PORT=443 \
    APACHE_ERROR_LOG_FILE=/proc/self/fd/2 \
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
    PHP_DISABLE_FUNCTIONS="exec,passthru,shell_exec,system,proc_open,popen" \
    # PHP Session Configuration
    PHP_SESSION_HANDLER=files \
    PHP_SESSION_PATH=/run/yii2/sessions \
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

#------------------------------------------------------------------------------
# BEGIN runtime configuration
#------------------------------------------------------------------------------

# Layer 02: Apache, PHP-FPM, PHP and supervisor configuration
COPY src/etc/apache2/ /etc/apache2/
COPY src/etc/php-fpm.d/ /usr/local/etc/php-fpm.d/
COPY src/etc/php/${BUILD_TYPE}.ini /usr/local/etc/php/conf.d/99-app.ini
COPY src/supervisor/supervisord.conf /etc/supervisor/
COPY src/supervisor/conf.d/ /etc/supervisor/conf.d/

# Layer 03: Entrypoint with its library, health script, healthcheck command and extension installer
COPY src/script/common/ /usr/local/lib/yii2-docker/common/
COPY src/script/health/ /usr/local/lib/yii2-docker/health/
COPY --chmod=0755 src/script/entrypoint.sh /usr/local/bin/entrypoint
COPY --chmod=0755 src/script/healthcheck.sh /usr/local/bin/healthcheck
COPY --chmod=0755 src/script/install-extensions.sh /usr/local/bin/install-extensions

# Layer 04: Directories, then an explicit list of Apache modules, configurations and sites
# /run/yii2 holds the runtime state; the entrypoint creates its content at every start for the running user, so it is
# world-writable with the sticky bit (like /tmp) instead of belonging to one user. Everything under /etc stays root's.
RUN install -d -o www-data -g www-data /var/www/.composer /var/www/.composer/cache /var/www/.npm /var/www/app \
    && install -d -m 1777 /run/yii2 \
    && chown -R root:root /etc/apache2 \
    && chmod 0755 /etc/apache2/ssl \
    && rm -rf /var/cache/apache2 /var/lib/php /var/lock/apache2 /var/run/apache2 \
    && rm -f /etc/apache2/conf-enabled/* /etc/apache2/sites-enabled/* /var/log/apache2/*.log \
    && a2dismod -q mpm_prefork mpm_worker \
    && a2enmod -q mpm_event alias env headers expires filter brotli http2 proxy proxy_fcgi rewrite setenvif ssl \
    && a2enconf -q 01-performance 02-security 03-ssl-tls 04-compression 05-php-fpm 06-logging 07-health \
    && a2ensite -q vhost \
    && apache2ctl configtest \
    && rm -rf /run/yii2/apache

#------------------------------------------------------------------------------
# END runtime configuration
#------------------------------------------------------------------------------

# Image metadata labels
LABEL apache.version="2.4" \
    build.type="${BUILD_TYPE}" \
    debian.version="trixie" \
    maintainer="yii2-extensions" \
    php.version="${PHP_VERSION}" \
    org.opencontainers.image.authors="@terabytesoftw" \
    org.opencontainers.image.base.name="php:${PHP_BASE_TAG}-fpm-trixie" \
    org.opencontainers.image.description="Debian Trixie + PHP ${PHP_VERSION} FPM + Apache with HTTP/2 support for Yii2 applications. Build type: ${BUILD_TYPE}" \
    org.opencontainers.image.documentation="https://github.com/yii2-extensions/docker-images#readme" \
    org.opencontainers.image.licenses="BSD-3-Clause" \
    org.opencontainers.image.source="https://github.com/yii2-extensions/docker-images" \
    org.opencontainers.image.title="Yii2 Apache Docker Image" \
    org.opencontainers.image.vendor="yii2-extensions"

WORKDIR /var/www/app

# The whole stack runs as www-data; --user <uid>:<gid> runs it as any user, --user root restores the root start
# hadolint ignore=DL3066
USER www-data

# Defaults of APACHE_HTTP_PORT and APACHE_HTTPS_PORT
EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 CMD ["healthcheck"]

ENTRYPOINT ["entrypoint"]

#------------------------------------------------------------------------------
# Smoke Tests (bake targets smoke-*, never pushed)
#------------------------------------------------------------------------------
FROM image AS smoke

# The smoke suite asserts the extension lists the image was built with
ARG PHP_VERSION
ARG PHP_EXTENSIONS_PROD
ARG PHP_EXTENSIONS_DEV
ARG PHP_EXTENSIONS_FULL

# The suite orchestrates as root and starts the stack as www-data, as an arbitrary UID and as root
# hadolint ignore=DL3002,DL3066
USER root

# The suite binds loopback ports; its own network namespace keeps concurrent smoke runs apart, because builders
# with host networking (the docker-container driver of CI) share the loopback interface between parallel RUN steps
RUN --network=none --mount=type=bind,source=tests,target=/opt/tests,readonly \
    bash /opt/tests/smoke.sh

#==============================================================================
# Final Stage (default target of a plain docker build)
#==============================================================================
FROM image AS final
