# Install a Docker environment

These images provide Apache, PHP-FPM, Composer and optional development tools for an existing Yii application.
They are not PHP extensions and are not installed with `composer require`.

## Requirements

- A running [Docker Engine](https://docs.docker.com/engine/install/) or Docker Desktop, with access to its daemon.
- A Linux container platform: `linux/amd64` or `linux/arm64` for the published stable images.
- An application with `composer.json`, preferably `composer.lock`, and a Web entry point such as `web/index.php`.
- A PHP version compatible with that application's Composer constraints. The image does not select a Yii version.
- Network access to GHCR for pulls and to dependency sources if Composer must install packages.

Docker Compose v2 or newer is optional. Building the image repository requires Docker Buildx with Bake support.
Do not change daemon permissions or use privileged containers to work around an inaccessible Docker service.

```bash
docker info
docker compose version
docker buildx version
```

## Select and pull an image

Read the [tag and variant tables](../README.md#tags). PHP 8.3, 8.4 and 8.5 have `prod`, `dev` and `full` variants;
PHP 8.6 is an experimental local/CI build, excluded from release publication. `latest` currently selects PHP 8.5
`prod`, which skips Composer at startup and is not the development default.

```bash
docker buildx imagetools inspect ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0
docker pull ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0
```

Use the exact tag or digest you inspected. A successful local Bake build does not prove that a tag is published.
A missing or denied manifest can mean a wrong tag or registry access problem; do not substitute an invented tag.
Rolling tags require a pull and container recreation to adopt updates.

## Match the document root

The image defaults to `/var/www/app/web`. The
[Yii 22.0 basic template on branch `22`](https://github.com/yiisoft/yii2-app-basic/tree/22/public) uses `public/`
instead; templates with `web/index.php` use the image default. From the Yii 22.0
application's root, prepare its writable directories and pass its actual document root:

For the `v2.0.0` image below, also adapt its virtual-host configuration so Apache reads the application's
`public/.htaccess` front-controller rules and serves published assets. Extract the configuration from the image you
pulled, adjust its public-directory paths and keep both files outside the document root:

```bash
mkdir -p docker runtime public/assets
docker run --rm --pull never --entrypoint cat ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0 \
    /etc/apache2/conf-available/vhost-common.conf > docker/vhost-common.original.conf
sed 's|/var/www/app/web|/var/www/app/public|g; s|(?!web/)|(?!public/)|g' \
    docker/vhost-common.original.conf > docker/vhost-common.conf
docker run -d --name yii22-app --user "$(id -u):$(id -g)" \
    -p 127.0.0.1:8080:80 -p 127.0.0.1:8443:443 \
    -e APACHE_DOCUMENT_ROOT=/var/www/app/public \
    --mount type=bind,src="$PWD",dst=/var/www/app \
    --mount type=bind,src="$PWD/docker/vhost-common.conf",dst=/etc/apache2/conf-available/vhost-common.conf,readonly \
    ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0
```

With Compose, add `APACHE_DOCUMENT_ROOT: /var/www/app/public` to the service environment and the same read-only
configuration mount. For another document root, adapt the replacement paths and the public-subtree exclusion in the
extracted configuration. The entrypoint's generic `web/assets` setup does not prepare every custom document root;
ensure the application's own public assets path is writable. Advanced templates similarly need the correct `frontend/web` or `backend/web` and their own runtime paths.
See the [Yii installation guide](https://yii2-framework.github.io/docs/guide/start-installation/) for application
creation; keep that separate from pulling a runtime image.

## Start the application

Use the [README quick start](../README.md#quick-start) for `docker run` or Compose. On Linux, run as your host UID:GID
and grant that user access to the mounted project. The entrypoint creates `runtime/`, `web/assets/` and
`web/uploads/`; Composer also needs write access when it installs dependencies. Avoid root startup on a developer
checkout: its Composer permission repair can recursively change project ownership.

An arbitrary UID has a temporary Composer home during automatic installation. For a manual Composer command,
set a writable cache explicitly as shown in [usage examples](examples.md#composer-and-console-commands).

Compose reads `.env` for interpolation; it does not automatically pass every value to the container. To use the
repository's [.env.example](../.env.example), copy it to an application-specific file, review its development
values, and reference it using `env_file:` or `docker run --env-file`. It is an example, not the image defaults:
notably it disables automatic certificate generation and enables displayed PHP errors.

Check container logs, `/health`, and an application route. A healthy PHP stack does not prove the application's
routes, database credentials or migrations work. [Configuration](configuration.md) describes startup behavior and
[testing](testing.md) explains isolated validation.

[Back to documentation](../README.md#documentation)
