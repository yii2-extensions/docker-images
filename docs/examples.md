# Use the images with an application

The commands below assume the [quick start](../README.md#quick-start) container named `app` and an application
mounted at `/var/www/app`. Use your actual container name for another environment.

## Composer and console commands

`docker exec` runs the command directly as the container user; it does not rerun the entrypoint. Automatic Composer
installation is skipped when `vendor/` exists, even if a lockfile changed. Reconcile dependencies explicitly:

```bash
docker exec -e COMPOSER_HOME=/tmp/app-composer app composer install --no-interaction --prefer-dist
docker exec app php yii help
```

Only run migrations against the database authorized for this application. The opt-in `YII_RUN_MIGRATIONS=true`
executes `php yii migrate --interactive=0` at startup, except when `YII_ENV=test`. Service waits check TCP access,
not credentials, schema readiness or database health. Use application-specific database variables in its PHP
configuration; the image's `DB_*_HOST` variables configure only the optional TCP wait.

A one-off command given to `docker run IMAGE COMMAND` still runs entrypoint initialization first. Disable unwanted
startup work explicitly for a test or diagnostic container:

```bash
docker run --rm --user "$(id -u):$(id -g)" \
    -e SKIP_COMPOSER_INSTALL=true -e SKIP_DB_WAIT=true -e YII_RUN_MIGRATIONS=false \
    --mount type=bind,src="$PWD",dst=/var/www/app \
    ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0 php -v
```

## Mounts and persistence

A bind mount of the project at `/var/www/app` hides files copied there by a derived image, including `vendor/`.
Do not expect dependencies baked into the image to remain visible under a full project mount. Install them into
the mounted project or select application-owned mounts deliberately.

The image does not declare application volumes. Files in a container's writable layer disappear when it is
removed. Persist uploads and any file-backed application state using paths chosen for the application. An empty
named volume is not guaranteed to be writable by an arbitrary UID; initialize only a new volume you own, and
verify permissions using the intended runtime user. Avoid `chmod -R 777` and recursive ownership changes to a
shared checkout.

PHP sessions default to `/run/yii2/sessions`. Treat runtime state and generated self-signed certificates as
ephemeral; use mounted certificates and an application-managed session store when persistence is required.
For an advanced template, set `APACHE_DOCUMENT_ROOT` to its actual `frontend/web` or `backend/web` and prepare
its corresponding runtime and assets directories; the default paths target a single `web/` entry point.
For `v2.0.0`, adapt the [directory override](installation.md#match-the-document-root) to that path as well.

## Configuration and diagnostics

```bash
docker logs --tail 100 app
docker inspect --format '{{json .State.Health}}' app
docker exec app healthcheck
docker exec app apache2ctl configtest
docker exec app php -v
docker exec app php -m
curl --fail http://127.0.0.1:8080/health
curl --fail --insecure https://127.0.0.1:8443/health
```

`--insecure` is for the generated local certificate only. Use trusted certificates for deployed applications.
`YII_ENV` and `YII_DEBUG` must be consumed by the application's bootstrap. The health response echoes `YII_ENV`
but does not prove that the application changed its own environment.

Most `PHP_*` variables configure the PHP-FPM pool, not CLI PHP. `docker exec app php -i` cannot verify the effective
Web request settings. Inspect a controlled application response for those; do not expose a public `phpinfo()` page.
For a CLI process, pass `php -d memory_limit=512M ...` as needed. See [Xdebug configuration](configuration.md#xdebug)
and [test commands](testing.md#test-an-application).

With `ENABLE_FPM_STATUS=true`, query the status from inside the container because the endpoint is loopback-only:

```bash
docker exec app curl --fail 'http://127.0.0.1/fpm-status?full'
```

Production `prod` uses HTTPS-only session cookies. For local HTTP testing, choose `dev` or supply an intentional
PHP configuration; do not diagnose missing HTTP session cookies as a database failure. OPcache in `prod` does not
validate file timestamps, so use `dev` for bind-mounted live edits.

## Stop an environment you own

For the quick-start container, inspect its name and mounts before removing it:

```bash
docker inspect --format '{{.Name}} {{json .Mounts}}' app
docker stop app
docker rm app
```

For Compose, run `docker compose down` from that application's project. It preserves named volumes by default.
Remove test volumes only when you created them for that test and no longer need their data. Do not use `prune`,
bulk removal, or another project's Compose configuration to clean up this environment.
