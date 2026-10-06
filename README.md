<!-- markdownlint-disable MD041 -->
<p align="center">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://www.yiiframework.com/image/design/logo/yii3_full_for_dark.svg">
        <source media="(prefers-color-scheme: light)" srcset="https://www.yiiframework.com/image/design/logo/yii3_full_for_light.svg">
        <img src="https://www.yiiframework.com/image/design/logo/yii3_full_for_light.svg" alt="Yii Framework" width="80%">
    </picture>
    <h1 align="center">Docker images</h1>
    <br>
</p>

<p align="center">
    <a href="https://github.com/yii2-extensions/docker-images/actions/workflows/build.yml" target="_blank">
        <img src="https://img.shields.io/github/actions/workflow/status/yii2-extensions/docker-images/build.yml?style=for-the-badge&logo=docker&logoColor=white&label=Build" alt="Build">
    </a>
    <a href="https://github.com/yii2-extensions/docker-images/actions/workflows/quality.yml" target="_blank">
        <img src="https://img.shields.io/github/actions/workflow/status/yii2-extensions/docker-images/quality.yml?style=for-the-badge&logo=github&label=Quality" alt="Quality">
    </a>
    <a href="https://github.com/yii2-extensions/docker-images/actions/workflows/security.yml" target="_blank">
        <img src="https://img.shields.io/github/actions/workflow/status/yii2-extensions/docker-images/security.yml?style=for-the-badge&logo=github&label=Security" alt="Security">
    </a>
</p>

<p align="center">
    <em>Debian Trixie images with Apache 2.4, PHP-FPM and HTTP/2 for Yii2 applications</em>
</p>
<!-- markdownlint-enable MD041 -->

Each image runs Apache (event MPM, HTTP/2, HTTPS) in front of PHP-FPM under `supervisord`, serves the application
from `/var/www/app/web`, and prepares the application at startup (directories, Composer, migrations) through an
entrypoint configured with environment variables.

## Tags

Images are published to `ghcr.io/yii2-extensions/apache` for `linux/amd64` and `linux/arm64`.

| Tag                                 | Example                  | Lifecycle                                                                                   |
| ----------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------- |
| `<php>-debian-<variant>`            | `8.5-debian-prod`        | Rolling: rebuilt weekly from the latest release to pick up PHP and Debian security patches. |
| `<php>-debian-<variant>-v<version>` | `8.5-debian-prod-v2.0.0` | Frozen at release time.                                                                     |
| `latest`                            | `latest`                 | Rolling: the `prod` variant of the newest stable PHP version (currently 8.5).               |

- PHP versions: `8.3`, `8.4`, `8.5`. PHP 8.6 is built in CI from its release candidate as an experimental job and is
  not published until it is stable.
- Variants: `prod`, `dev`, `full`.

Use a rolling tag to receive security updates automatically, or a frozen tag for reproducible deployments.

## Quick start

Run the `dev` variant against an application in the current directory. On Linux, pass your own user so the files the
container creates (`vendor/`, `runtime/`, `web/assets/`) belong to you:

```bash
docker run -d --name app --user "$(id -u):$(id -g)" -p 8080:80 -p 8443:443 -v "$PWD":/var/www/app \
    ghcr.io/yii2-extensions/apache:8.5-debian-dev
```

The application answers on `http://localhost:8080` and, with a generated self-signed certificate, on
`https://localhost:8443`. Composer installs the dependencies at startup when `vendor/` is missing, as the container
user, so the project directory must be writable by it. Without `--user` the stack runs as `www-data` (UID 33), which
suits Docker Desktop and named volumes. On runtimes that keep ports below 1024 privileged (Kubernetes, `--network
host`), set `APACHE_HTTP_PORT=8080` and `APACHE_HTTPS_PORT=8443` and map `-p 8080:8080 -p 8443:8443` instead.

With Docker Compose:

```yaml
services:
  app:
    image: ghcr.io/yii2-extensions/apache:8.5-debian-dev
    user: "${UID:-1000}:${GID:-1000}"
    ports:
      - "8080:80"
      - "8443:443"
    volumes:
      - .:/var/www/app
    environment:
      YII_ENV: dev
      YII_DEBUG: "1"
```

For production, build an application image on top of `prod` so the code and its dependencies are part of the image:

```dockerfile
FROM ghcr.io/yii2-extensions/apache:8.5-debian-prod-v2.0.0

COPY --chown=www-data:www-data . /var/www/app
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress
```

## Variants

| Variant | PHP extensions                                                                    | Tools                                                                      |
| ------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `prod`  | apcu, bcmath, gd, imagick, intl, opcache, pcntl, pdo_mysql, pdo_pgsql, redis, zip | Composer                                                                   |
| `dev`   | `prod` plus memcached, mongodb, soap, xdebug, yaml                                | Composer, Node.js 24, npm                                                  |
| `full`  | `dev` plus oci8, pdo_oci, pdo_sqlsrv, sqlsrv, tidy                                | Composer, Node.js 24, npm, Oracle Instant Client, Microsoft ODBC Driver 18 |

- `prod`: OPcache without timestamp validation and with the tracing JIT, session cookies restricted to HTTPS
  (`session.cookie_secure`) and `SameSite=Strict`, no Composer install at startup by default.
- `dev`: OPcache revalidates files on every request, JIT disabled, Xdebug loaded.
- `full`: `dev` plus the Oracle and SQL Server drivers and assertions enabled, JIT disabled as in `dev` (Xdebug
  is loaded); intended for test suites that cover every database driver.

Compressed size of the PHP 8.5 images:

| Variant | v1.1.0    | v2.0.0    |
| ------- | --------- | --------- |
| `prod`  | 232.9 MiB | 125.1 MiB |
| `dev`   | 235.3 MiB | 175.4 MiB |
| `full`  | 275.6 MiB | 215.4 MiB |

## Configuration

The most common settings are listed below. See the [configuration reference](docs/configuration.md) for every
variable, its default and the startup sequence.

| Variable                 | Default                              | Description                                                    |
| ------------------------ | ------------------------------------ | -------------------------------------------------------------- |
| `APACHE_DOCUMENT_ROOT`   | `/var/www/app/web`                   | Document root.                                                 |
| `APACHE_HTTP_PORT`       | `80`                                 | HTTP port inside the container.                                |
| `APACHE_HTTPS_PORT`      | `443`                                | HTTPS port inside the container.                               |
| `APACHE_SSL_ENABLED`     | `true`                               | HTTPS with HTTP/2 on `APACHE_HTTPS_PORT`.                      |
| `APACHE_SSL_REDIRECT`    | `false`                              | Redirect HTTP to HTTPS.                                        |
| `SSL_AUTO_GENERATE`      | `true`                               | Generate a self-signed certificate when none is mounted.       |
| `SSL_CERT_FILE`          | `/etc/apache2/ssl/cert.pem`          | Mounted certificate, readable by the container user.           |
| `SSL_KEY_FILE`           | `/etc/apache2/ssl/key.pem`           | Mounted private key, readable by the container user.           |
| `SKIP_COMPOSER_INSTALL`  | `true` for `prod`, `false` otherwise | Skip `composer install` at startup.                            |
| `YII_RUN_MIGRATIONS`     | `false`                              | Run `yii migrate` at startup.                                  |
| `WAIT_FOR_SERVICES`      | `false`                              | Wait for the `DB_*_HOST` services before starting.             |
| `ENABLE_HEALTH_ENDPOINT` | `true`                               | Serve the public health endpoint at `HEALTHCHECK_PATH`.        |
| `ENABLE_FPM_STATUS`      | `false`                              | Serve the PHP-FPM status and ping pages to loopback only.      |
| `PHP_MEMORY_LIMIT`       | `256M`                               | PHP memory limit; every `PHP_*` setting is listed in the docs. |

To use your own certificate, mount it and point the entrypoint at it:

```bash
docker run -d -p 80:80 -p 443:443 \
    -v /path/to/certs:/run/certs:ro \
    -e SSL_AUTO_GENERATE=false \
    -e SSL_CERT_FILE=/run/certs/fullchain.pem \
    -e SSL_KEY_FILE=/run/certs/privkey.pem \
    -e APACHE_SSL_REDIRECT=true \
    my-app
```

## Users and privileges

The whole stack (the entrypoint, `supervisord`, Apache and PHP-FPM) runs as the container user, and no process is
root:

- **`www-data`** (default, the image declares `USER www-data`).
- **Any UID**, with `--user <uid>:<gid>` or Compose `user:`. The UID needs no account in the image, so files created
  in a bind-mounted project belong to the host user. The entrypoint cannot change ownership in this mode; when the
  application directory is not writable it says so and names the remedy.
- **Root**, as an explicit opt-in with `--user root`: the entrypoint initializes as root (directories, `FIX_PERMS`
  before a Composer install), then Apache and PHP-FPM drop their workers to `www-data`, as in v1. Nothing root
  sources, executes or loads may be written by `www-data`, and the generated private key is readable by root only.

Runtime state (pid files, sockets, the Apache runtime environment, generated certificates, PHP sessions and temporary
files) lives under `/run/yii2` and is created at every start for the running user. In the two non-root modes no
process can gain root, so the class of privilege escalation that the root mode must guard against does not exist.

Ports 80 and 443 work as a non-root user under `docker run`, because Docker allows unprivileged processes to bind
every port. Kubernetes, `--network host` and other runtimes that keep ports below 1024 privileged need
`APACHE_HTTP_PORT` and `APACHE_HTTPS_PORT` (for example `8080` and `8443`); the entrypoint stops with that remedy when
the configured port cannot be bound. The container side of the port mappings changes with them: `-p 8080:80` becomes
`-p 8080:8080`. See the [configuration reference](docs/configuration.md#users-and-privileges) for the read-only root
filesystem flags.

## Health checks

- `GET /health` returns a JSON status document produced by PHP-FPM. Change the path with `HEALTHCHECK_PATH` or
  disable it with `ENABLE_HEALTH_ENDPOINT=false`.
- The Docker `HEALTHCHECK` runs the `healthcheck` command, which requests the reserved, loopback-only `/__health`
  path through Apache and PHP-FPM. The container becomes unhealthy when either of them stops answering.

## Extending the image

The images contain neither the compiler toolchain nor the PHP source tarball. The included `install-extensions`
command compiles extensions in a derived image in one step:

```dockerfile
FROM ghcr.io/yii2-extensions/apache:8.5-debian-prod

USER root
RUN install-extensions amqp sockets
USER www-data
```

The image runs as `www-data`, so every step that installs packages or extensions needs `USER root` first, and the
image should switch back to `USER www-data` afterwards; `install-extensions` stops with that hint when it is not root.

It accepts the extension names and version syntax of
[`install-php-extensions`](https://github.com/mlocati/docker-php-extension-installer) (PECL and bundled extensions).
It downloads the exact PHP source the image was built from and verifies its SHA-256 checksum, installs the
toolchain, builds the extensions, then removes the toolchain, the source and the build-only packages while keeping
the shared libraries the new extensions load. The build fails when a library is left unresolved or PHP reports a
startup warning. The example above adds a layer of about 2 MB.

Ghostscript is not included, so Imagick reads and writes raster formats (JPEG, PNG, WebP, GIF and others) but not
PDF, PS or EPS. Add it in a derived image when you need them:

```dockerfile
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ghostscript && rm -rf /var/lib/apt/lists/*
USER www-data
```

## Upgrading from v1

Version 2 contains breaking changes. Review each item before switching tags.

- **No toolchain in the image.** Images ship without compilers and PHP sources. Derived images that compile
  extensions use the included `install-extensions` command (see [Extending the image](#extending-the-image)).
- **Runs as `www-data`.** The image declares `USER www-data` and the whole stack runs as the container user; `docker
exec` defaults to `www-data`. Use `--user "$(id -u):$(id -g)"` for bind mounts on Linux (v1 changed the owner of the
  project to `www-data` instead), or `--user root` for the v1 behavior (root initialization, `FIX_PERMS`, workers as
  `www-data`). Derived images need `USER root` before installing packages or extensions and `USER www-data` after;
  application files copied into a derived image need `COPY --chown=www-data:www-data`.
- **Runtime state moved to `/run/yii2`.** Pid files, the PHP-FPM socket (`/run/yii2/php/php-fpm.sock`), the
  supervisor socket, PHP sessions (`PHP_SESSION_PATH=/run/yii2/sessions`), PHP temporary files and the generated
  self-signed certificate (`/run/yii2/ssl`) are created at every start. Generated certificates are no longer written
  to `SSL_DIR` and do not survive a restart; mounted certificates must be readable by the container user, otherwise the
  container serves HTTP only and logs why. `/etc/apache2` and `/etc/apache2/ssl` belong to root.
- **No `sudo`, `gosu`, `vim-tiny` or `brotli` CLI.** `www-data` no longer has passwordless `sudo`, and the entrypoint
  no longer re-executes itself as root.
- **Node.js is no longer downloaded at startup.** `dev` and `full` include Node.js 24 and npm; `prod` does not. Build
  front-end assets in your application image or in a separate build stage.
- **`prod` skips `composer install` by default.** Install dependencies in the application image, or set
  `SKIP_COMPOSER_INSTALL=false` to restore the v1 behavior.
- **`FAIL_ON_*` flags are honored.** `FAIL_ON_SERVICE_TIMEOUT` and `FAIL_ON_COMPOSER_ERROR` default to `false`, so an
  unreachable service or a failed Composer install is logged and startup continues; v1 aborted the container. Set them
  to `true` to keep failing fast. `FAIL_ON_MIGRATION_ERROR` defaults to `true`.
- **Health endpoint served from the image.** Nothing is written to `web/` any more; remove the `web/health/`
  directory that v1 created in the application. `/__health` is reserved. The container now turns unhealthy when
  PHP-FPM is down.
- **No User-Agent filter.** Requests from clients whose User-Agent contains `bot`, `curl`, `wget`, `python` or `scan`
  are no longer rejected with 403. Block unwanted clients at your proxy or firewall if needed.
- **Single virtual host file.** `sites-available/vhost-ssl.conf` and `sites-available/vhost-ssl-full.conf` are gone;
  `sites-available/vhost.conf` is driven by Apache defines and the entrypoint no longer rewrites configuration files.
  `APACHE_HTTPS_PORT` is not opened when `APACHE_SSL_ENABLED=false`. Images that replaced or patched these files must
  be updated.
- **Apache defaults.** The ineffective `<LimitExcept>` block, the inert global rewrite rules and
  `07-rate-limiting.conf` are removed. Debian's default configuration snippets are disabled, so the `Server` header is
  `Apache` and nothing is logged to files inside the container.
- **Shorter `PHP_DISABLE_FUNCTIONS` default.** Web requests now block only the shell functions (`exec`, `passthru`,
  `shell_exec`, `system`, `proc_open`, `popen`); `parse_ini_file` and `show_source` are available again. The list is
  applied to the PHP-FPM master instead of the pool, so pools you add inherit it and cannot re-enable its functions
  with `php_admin_value[disable_functions]`; set the variable instead.
- **PHP-FPM status is opt-in.** Set `ENABLE_FPM_STATUS=true` to serve `PHP_FPM_STATUS_PATH` and `PHP_FPM_PING_PATH`
  to loopback only. `/fpm-status-full` is replaced by `?full` on the status path.
- **SQL Server drivers.** `sqlsrv` and `pdo_sqlsrv` 5.13 come from the extension installer instead of a patched 5.12.0
  build.
- **Xdebug configuration.** The unused `xdebug.ini` is removed; configure Xdebug with `XDEBUG_MODE` and
  `XDEBUG_CONFIG` (see the [configuration reference](docs/configuration.md#xdebug)).
- **No JIT in `full`.** Xdebug made PHP disable the tracing JIT anyway and warn at every startup; `full` now turns it
  off like `dev`. `prod` keeps the tracing JIT.
- **Inert Apache variables removed.** `APACHE_RUN_USER`, `APACHE_RUN_GROUP`, `APACHE_RUN_DIR`, `APACHE_PID_FILE` and
  `APACHE_LOCK_DIR` are no longer in the image environment. `/etc/apache2/envvars` always overrode them, so setting
  them never had an effect; drop them from your configuration.
- **Published assets are served.** The Yii directory protection is anchored at `/var/www/app`, so files under
  `web/assets/<hash>/widgets/` or `web/assets/<hash>/vendor/` (jQuery UI, for example) no longer return 403.

`APACHE_SSL_REDIRECT`, `SSL_AUTO_GENERATE`, `SSL_CERT_FILE`, `SSL_KEY_FILE`, `SSL_DIR`, `SSL_CHAIN_FILE`,
`APACHE_DISABLE_OCSP_STAPLING`, `DEBUG_ENTRYPOINT`, `FORCE_COMPOSER_INSTALL`, `FIX_PERMS` and every `APACHE_*` and
`PHP_*` tuning variable keep their names, defaults and behavior.

## Development

`docker-bake.hcl` is the single source of truth for PHP versions, variants and tags. Adding a PHP version is one
entry in its `PHP` variable; an entry whose `base` differs from `version` (a release candidate such as `8.6-rc`) is
experimental, excluded from the default group and never published.

```bash
# Build every stable image (PHP 8.3 to 8.5, all variants)
docker buildx bake

# Build one image and load it into the local image store
docker buildx bake image-8-5-dev --load

# Build one image and run the smoke tests (tests/smoke.sh) inside a build stage
docker buildx bake smoke-8-5-prod

# Build the experimental PHP 8.6 image
docker buildx bake image-8-6-prod --load

# Print every image target as JSON
docker buildx bake --print image
```

Continuous integration:

| Workflow       | Trigger                                    | Purpose                                                                                     |
| -------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `build.yml`    | Pull requests, pushes to `main`            | Builds every PHP version on both architectures and runs the smoke tests.                    |
| `release.yml`  | Tags `vX.Y.Z`, weekly schedule, manual run | Publishes a release; the weekly run rebuilds the latest release and moves the rolling tags. |
| `quality.yml`  | Pull requests, pushes                      | Organization quality checks, Hadolint and ShellCheck.                                       |
| `security.yml` | Pull requests, pushes                      | Organization security checks.                                                               |

## Package information

[![GitHub Release](https://img.shields.io/github/v/release/yii2-extensions/docker-images?style=for-the-badge&logo=git&logoColor=white&label=Release)](https://github.com/yii2-extensions/docker-images/releases)

## Our social networks

[![Follow on X](https://img.shields.io/badge/-Follow%20on%20X-1DA1F2.svg?style=for-the-badge&logo=x&logoColor=white&labelColor=000000)](https://x.com/Terabytesoftw)

## License

[![License](https://img.shields.io/badge/License-BSD--3--Clause-brightgreen.svg?style=for-the-badge&logo=opensourceinitiative&logoColor=white&labelColor=555555)](LICENSE)
