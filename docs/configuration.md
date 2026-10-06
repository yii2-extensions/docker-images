# Configuration reference

Every setting is an environment variable read when the container starts. The default is the value set by the image
or, when the image does not set the variable, the value the entrypoint falls back to.

## Startup sequence

The entrypoint runs these steps in order and then starts the command.

1. Prints a banner with the variant, PHP version, user, `YII_ENV` and `YII_DEBUG`.
2. Creates the runtime state in `/run/yii2` and the application directories, configures Apache, fixes permissions (root).
3. Waits for the configured services, when enabled.
4. Runs `composer install`, unless skipped.
5. Runs the Yii migrations, when enabled.
6. Starts `supervisord` (Apache and PHP-FPM) or, when a command is given, runs that command instead.

Step 2 creates `runtime`, `web/assets` and `web/uploads` under `/var/www/app` and writes the Apache ports and defines
for HTTPS, the health endpoint and the PHP-FPM status. As root it also creates the `www-data` home directories and
assigns `runtime` and `web/assets` to `www-data`, skipping any path that is or passes through a symbolic link; as any
other user it creates what it can and logs the remedy for what it cannot write. Apache configuration lives under `/etc/apache2` and is static: the entrypoint only
selects which sections apply through Apache defines, it never rewrites configuration files.

## Users and privileges

The stack runs as the container user: `www-data` by default, any UID:GID with `--user` (no passwd entry needed), or
root with `--user root`, where Apache and PHP-FPM drop their workers to `www-data`. `supervisord` cannot assign
programs to another user unless it is root, so custom programs in `/etc/supervisor/conf.d` only keep `user=` lines in
root mode.

| Path                   | Content                                                                        |
| ---------------------- | ------------------------------------------------------------------------------ |
| `/run/yii2/apache`     | `runtime.env` (defines, ports, certificate paths), pid file, locks, SSL caches |
| `/run/yii2/php`        | PHP-FPM socket                                                                 |
| `/run/yii2/supervisor` | `supervisord` pid file and control socket                                      |
| `/run/yii2/ssl`        | Generated self-signed certificate and key                                      |
| `/run/yii2/sessions`   | PHP sessions (`PHP_SESSION_PATH`)                                              |
| `/run/yii2/tmp`        | PHP upload and temporary files                                                 |

The entrypoint creates these directories at every start for the running user; in root mode they belong to root,
except `sessions` and `tmp`, which belong to `www-data`. `/etc/apache2/envvars` sources `runtime.env` only when the
calling user owns it, so run `docker exec` as the container user (the default) to get the same Apache configuration.
In root mode nothing that root sources, executes or loads as configuration is writable by `www-data`; in the
non-root modes no process can become root.

A read-only root filesystem works with tmpfs mounts for the runtime state and the temporary directory, plus writable
application directories when the application is part of the image:

```bash
docker run -d --read-only --tmpfs /run/yii2:mode=1777 --tmpfs /tmp:mode=1777 \
    --tmpfs /var/www/app/runtime:uid=33,gid=33 --tmpfs /var/www/app/web/assets:uid=33,gid=33 \
    -p 8080:80 -p 8443:443 my-app
```

Ports 80 and 443 can be bound by a non-root user under `docker run` (Docker sets
`net.ipv4.ip_unprivileged_port_start=0`). Kubernetes and `--network host` usually keep the 1024 limit: set
`APACHE_HTTP_PORT=8080` and `APACHE_HTTPS_PORT=8443` and map or expose those ports. The entrypoint stops with this
remedy when a configured port is privileged for the running user.

## Entrypoint

| Variable             | Default      | Description                                                                                           |
| -------------------- | ------------ | ----------------------------------------------------------------------------------------------------- |
| `DEBUG_ENTRYPOINT`   | `false`      | `true` prints debug messages from the entrypoint.                                                     |
| `CUSTOM_DIRECTORIES` | empty        | Comma-separated list of extra directories to create and assign to `www-data` at startup (root only).  |
| `BUILD_TYPE`         | variant      | Set by the image to `prod`, `dev` or `full`. Selects the Composer defaults below; do not override it. |
| `SERVICE_TYPE`       | `apache-fpm` | Set by the image. Apache is configured only for `apache-fpm`; do not override it.                     |
| `YII_ENV`            | empty        | Shown in the banner and the health response. `test` enables the service wait and skips migrations.    |
| `YII_DEBUG`          | empty        | Shown in the banner.                                                                                  |

## Service wait

The entrypoint opens a TCP connection to every configured host until it succeeds or the timeout expires.

| Variable                  | Default | Description                                                                             |
| ------------------------- | ------- | --------------------------------------------------------------------------------------- |
| `WAIT_FOR_SERVICES`       | `false` | `true` enables the wait. It is also enabled when `YII_ENV=test`.                        |
| `SKIP_DB_WAIT`            | `false` | `true` disables the wait in every case.                                                 |
| `SERVICE_WAIT_TIMEOUT`    | `30`    | Seconds to wait for each service.                                                       |
| `FAIL_ON_SERVICE_TIMEOUT` | `false` | `true` exits with status 1 when a service is not reachable; `false` logs and continues. |

Only services whose host variable is set are checked.

| Host variable     | Port variable     | Default port |
| ----------------- | ----------------- | ------------ |
| `DB_MYSQL_HOST`   | `DB_MYSQL_PORT`   | `3306`       |
| `DB_PGSQL_HOST`   | `DB_PGSQL_PORT`   | `5432`       |
| `DB_REDIS_HOST`   | `DB_REDIS_PORT`   | `6379`       |
| `DB_MONGODB_HOST` | `DB_MONGODB_PORT` | `27017`      |
| `DB_MSSQL_HOST`   | `DB_MSSQL_PORT`   | `1433`       |
| `DB_ORACLE_HOST`  | `DB_ORACLE_PORT`  | `1521`       |

## Composer

`composer install` runs in `/var/www/app` as `www-data` (or as the current user when not root), only when
`composer.json` exists, with `--no-interaction --no-progress --optimize-autoloader --prefer-dist`. `--no-dev` is added
when `YII_ENV=prod` or `BUILD_TYPE=prod`.

| Variable                 | Default                              | Description                                                                                                  |
| ------------------------ | ------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `SKIP_COMPOSER_INSTALL`  | `true` for `prod`, `false` otherwise | `true` skips the install. An explicit value always wins over the variant default.                            |
| `FORCE_COMPOSER_INSTALL` | `false`                              | `true` installs even when `vendor/` already exists.                                                          |
| `FIX_PERMS`              | `true`                               | As root, `true` runs `chown -R www-data:www-data` and `chmod -R g+rwX` on `/var/www/app` before the install. |
| `FAIL_ON_COMPOSER_ERROR` | `false`                              | `true` exits with status 1 when the install fails; `false` logs and continues.                               |
| `COMPOSER_HOME`          | `/var/www/.composer`                 | Set by the image.                                                                                            |

`FIX_PERMS` acts only when the install runs (not skipped, `composer.json` present, no `vendor/` unless
`FORCE_COMPOSER_INSTALL=true`), as in v1: it gives `www-data` write access for Composer and leaves the application
alone otherwise, so the `prod` default never makes the code writable by the web server. In root mode the entrypoint
always hands `runtime/` and `web/assets/` to `www-data` when they exist.

## Yii migrations

| Variable                  | Default | Description                                                                                      |
| ------------------------- | ------- | ------------------------------------------------------------------------------------------------ |
| `YII_RUN_MIGRATIONS`      | `false` | `true` runs `php yii migrate --interactive=0` as `www-data`. Skipped without `yii` or in `test`. |
| `FAIL_ON_MIGRATION_ERROR` | `true`  | `true` exits with status 1 when a migration fails; `false` logs and continues.                   |

## Apache and HTTPS

| Variable                       | Default               | Description                                                                                                             |
| ------------------------------ | --------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `APACHE_HTTP_PORT`             | `80`                  | HTTP port; the healthcheck uses it.                                                                                     |
| `APACHE_HTTPS_PORT`            | `443`                 | HTTPS listener and virtual host port.                                                                                   |
| `APACHE_SSL_ENABLED`           | `true`                | `true` serves HTTPS with HTTP/2 on `APACHE_HTTPS_PORT`. `false` serves HTTP only and does not open `APACHE_HTTPS_PORT`. |
| `APACHE_SSL_REDIRECT`          | `false`               | `true` redirects HTTP to HTTPS with status 301 (see below).                                                             |
| `SSL_AUTO_GENERATE`            | `true`                | `true` generates a self-signed certificate (RSA 2048, valid 365 days) when the files are missing.                       |
| `SSL_DIR`                      | `/etc/apache2/ssl`    | Searched for mounted certificates and `openssl.conf`.                                                                   |
| `SSL_CERT_FILE`                | `${SSL_DIR}/cert.pem` | Certificate file.                                                                                                       |
| `SSL_KEY_FILE`                 | `${SSL_DIR}/key.pem`  | Private key file.                                                                                                       |
| `SSL_CHAIN_FILE`               | empty                 | Optional chain file. A path that does not exist is ignored with a warning.                                              |
| `APACHE_DISABLE_OCSP_STAPLING` | `false`               | `true` disables OCSP stapling.                                                                                          |
| `APACHE_DOCUMENT_ROOT`         | `/var/www/app/web`    | Document root.                                                                                                          |
| `APACHE_ACCESS_LOG`            | `/proc/self/fd/1`     | Access log destination (JSON lines).                                                                                    |
| `APACHE_ERROR_LOG_FILE`        | `/proc/self/fd/2`     | Error log destination.                                                                                                  |
| `APACHE_ARGUMENTS`             | empty                 | Extra arguments for `apache2ctl`; the entrypoint appends its own `-D` defines.                                          |

When HTTPS is enabled but no certificate is usable (files missing and `SSL_AUTO_GENERATE=false`, or generation
failed), the container starts HTTP only and logs a warning.

With `APACHE_SSL_REDIRECT=true`, requests for `localhost` are redirected to `https://localhost:8443`, matching a
`8443:443` port mapping; requests for any other host name are redirected to port 443. With another `APACHE_HTTPS_PORT`, every host is
redirected to that port. The internal `/__health`
endpoint is never redirected.

OCSP stapling is enabled only for certificates you provide: when `SSL_AUTO_GENERATE` is not `true` and
`APACHE_DISABLE_OCSP_STAPLING` is not `true`.

### MPM event

| Variable                             | Default |
| ------------------------------------ | ------- |
| `APACHE_ASYNC_REQUEST_WORKER_FACTOR` | `2`     |
| `APACHE_GRACEFUL_SHUTDOWN_TIMEOUT`   | `10`    |
| `APACHE_LISTEN_BACKLOG`              | `511`   |
| `APACHE_MAX_CONNECTIONS_PER_CHILD`   | `5000`  |
| `APACHE_MAX_REQUEST_WORKERS`         | `800`   |
| `APACHE_MAX_SPARE_THREADS`           | `100`   |
| `APACHE_MIN_SPARE_THREADS`           | `25`    |
| `APACHE_SERVER_LIMIT`                | `32`    |
| `APACHE_START_SERVERS`               | `4`     |
| `APACHE_THREAD_LIMIT`                | `64`    |
| `APACHE_THREADS_PER_CHILD`           | `25`    |

Each variable maps to the [MPM directive](https://httpd.apache.org/docs/2.4/mod/mpm_common.html) of the same name.

## Health endpoints

The health script is part of the image and runs through Apache and PHP-FPM. Application rewrite rules and
`.htaccess` files do not apply to it, nothing is written to the application directory, and served health requests are
not written to the access log.

| Variable                 | Default    | Description                                                                  |
| ------------------------ | ---------- | ---------------------------------------------------------------------------- |
| `ENABLE_HEALTH_ENDPOINT` | `true`     | `false` disables the public endpoint; the path then reaches the application. |
| `HEALTHCHECK_PATH`       | `/health`  | Public endpoint path, answered with and without a trailing slash.            |
| `SERVICE_NAME`           | `yii2-app` | `service` field of the response.                                             |
| `APP_VERSION`            | `unknown`  | `version` field of the response.                                             |

The response is a JSON document with the fields `status` (`healthy`), `timestamp`, `service`, `version`,
`environment` (`YII_ENV`), `php_version` and `checks` (whether `pdo`, `intl` and `opcache` are loaded).

The path `/__health` is reserved. It is always enabled, answers loopback requests only and backs the `healthcheck`
command that the Docker `HEALTHCHECK` runs, so the container turns unhealthy when Apache or PHP-FPM stops answering.
It does not depend on `ENABLE_HEALTH_ENDPOINT` or `APACHE_SSL_REDIRECT`.

## PHP-FPM status

| Variable              | Default       | Description                                                       |
| --------------------- | ------------- | ----------------------------------------------------------------- |
| `ENABLE_FPM_STATUS`   | `false`       | `true` serves the PHP-FPM status and ping pages to loopback only. |
| `PHP_FPM_STATUS_PATH` | `/fpm-status` | Status page path. Append `?full` for the per-process status.      |
| `PHP_FPM_PING_PATH`   | `/fpm-ping`   | Ping path; answers `pong`.                                        |

Query them from inside the container:

```bash
docker exec app curl -s 'http://127.0.0.1/fpm-status?full'
```

## PHP

These values are applied to web requests through the PHP-FPM pool. The CLI uses the variant `php.ini` settings.
`PHP_DISABLE_FUNCTIONS` is passed to the PHP-FPM master on its command line instead, so it also applies to any pool
you add. A pool can disable more functions with `php_admin_value[disable_functions]` but cannot re-enable the ones in
the variable; change the variable instead (empty disables nothing). When the variable is removed from the container
environment (`-e PHP_DISABLE_FUNCTIONS` or Compose `environment: [PHP_DISABLE_FUNCTIONS]` while it is unset on the
host), the entrypoint applies the default list.

| Variable                     | Default                                           |
| ---------------------------- | ------------------------------------------------- |
| `PHP_ALLOW_URL_FOPEN`        | `0`                                               |
| `PHP_ALLOW_URL_INCLUDE`      | `0`                                               |
| `PHP_DATE_TIMEZONE`          | `UTC`                                             |
| `PHP_DISABLE_FUNCTIONS`      | `exec,passthru,shell_exec,system,proc_open,popen` |
| `PHP_DISPLAY_ERRORS`         | `0`                                               |
| `PHP_DISPLAY_STARTUP_ERRORS` | `0`                                               |
| `PHP_ERROR_LOG`              | `/proc/self/fd/2`                                 |
| `PHP_ERROR_REPORTING`        | `E_ALL & ~E_DEPRECATED`                           |
| `PHP_EXPOSE`                 | `0`                                               |
| `PHP_LOG_ERRORS`             | `1`                                               |
| `PHP_MAX_EXECUTION_TIME`     | `30`                                              |
| `PHP_MAX_FILE_UPLOADS`       | `20`                                              |
| `PHP_MAX_INPUT_TIME`         | `60`                                              |
| `PHP_MAX_INPUT_VARS`         | `1000`                                            |
| `PHP_MEMORY_LIMIT`           | `256M`                                            |
| `PHP_POST_MAX_SIZE`          | `50M`                                             |
| `PHP_SESSION_HANDLER`        | `files`                                           |
| `PHP_SESSION_PATH`           | `/run/yii2/sessions`                              |
| `PHP_UPLOAD_MAX_FILESIZE`    | `50M`                                             |

## PHP-FPM pool

| Variable                  | Default           |
| ------------------------- | ----------------- |
| `PHP_FPM_ACCESS_LOG`      | `/proc/self/fd/1` |
| `PHP_FPM_CATCH_OUTPUT`    | `yes`             |
| `PHP_FPM_IDLE_TIMEOUT`    | `10s`             |
| `PHP_FPM_LOG_LEVEL`       | `warning`         |
| `PHP_FPM_MAX_CHILDREN`    | `50`              |
| `PHP_FPM_MAX_REQUESTS`    | `500`             |
| `PHP_FPM_MAX_SPARE`       | `35`              |
| `PHP_FPM_MIN_SPARE`       | `5`               |
| `PHP_FPM_PM`              | `dynamic`         |
| `PHP_FPM_REQUEST_TIMEOUT` | `30`              |
| `PHP_FPM_RLIMIT_FILES`    | `131072`          |
| `PHP_FPM_SLOWLOG_TIMEOUT` | `5s`              |
| `PHP_FPM_START_SERVERS`   | `5`               |

Each variable maps to the [pool directive](https://www.php.net/manual/en/install.fpm.configuration.php) of the same
role (`pm`, `pm.max_children`, `request_terminate_timeout`, `rlimit_files` and so on). The pool keeps the container
environment (`clear_env = no`), so PHP code reads every variable passed to the container.

## Xdebug

Xdebug is loaded in `dev` and `full` only. The image ships no Xdebug settings; configure it with the standard
[`XDEBUG_MODE`](https://xdebug.org/docs/all_settings#mode) and
[`XDEBUG_CONFIG`](https://xdebug.org/docs/all_settings#XDEBUG_CONFIG) environment variables:

```bash
docker run -d -p 8080:80 -v "$PWD":/var/www/app \
    --add-host=host.docker.internal:host-gateway \
    -e XDEBUG_MODE=debug \
    -e XDEBUG_CONFIG="client_host=host.docker.internal client_port=9003" \
    ghcr.io/yii2-extensions/apache:8.5-debian-dev
```
