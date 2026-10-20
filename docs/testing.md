# Validate a Docker environment

Validate the image stack separately from the application. The portable helper checks Apache, PHP-FPM and filesystem
behavior; it does not install Yii, connect to a database or replace application tests.

## Repository quality and security jobs

This Docker-only package has no Composer or PHP test suite. CI runs the shared repository quality checks, Hadolint,
ShellCheck, workflow security, and Docker Buildx image builds. Run the available quality tools from the repository root:

```bash
actionlint
codespell --config .github/linters/.codespellrc --skip=./.git,./vendor/*,./node_modules/*,./internal/*,./runtime/*
editorconfig-checker -config .github/linters/.editorconfig-checker.json
markdownlint-cli2 --config .github/linters/.markdown-lint.yml '**/*.md' '#vendor/**' '#node_modules/**' '#internal/**' '#runtime/**'
prettier --check '**/*.md' '**/*.{yml,yaml}' '!runtime/**' '!internal/**'
yamllint -d 'extends: default
rules:
  comments:
    min-spaces-from-content: 1
  line-length: disable
  truthy: disable' .github
bash .github/scripts/lint.sh hadolint
bash .github/scripts/lint.sh shellcheck
zizmor --persona=pedantic .github
gitleaks git --config .github/linters/.gitleaks.toml --redact
```

These commands require their named CLIs on `PATH`; the Docker image validation/build steps below require Docker. The shared
workflow's pinned tool versions and hosted security credentials are separate from this local run.

## Run an isolated image check

From a source checkout, pull a verified release and run the skill's portable helper:

```bash
docker pull ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0
bash skills/yii2-docker-environment/scripts/validate.sh \
    ghcr.io/yii2-extensions/apache:8.5-debian-dev-v2.0.0
```

Requirements: Bash, Docker with a reachable local rootful Linux daemon without user-namespace remapping, curl,
Python 3, and a non-root host user. The image must already exist locally. Rootless Docker and `userns-remap` change
[bind-mount UID/GID mapping](https://docs.docker.com/engine/security/rootless/uid-gid-mapping/); the helper rejects
those modes before creating a fixture or container. These are helper restrictions, not an image compatibility
claim; use application-specific mount ownership when running images with remapped UIDs. Do not change daemon
configuration just to run the helper. The helper uses a temporary dependency-free fixture, the host UID:GID, an exclusive
container ID, and dynamically allocated loopback HTTP/HTTPS ports. It checks application output, effective FPM
memory settings, HTTPS, the internal health command, blocked external access to `/__health`, CLI execution,
expected tools, and host file ownership. It removes its own container and fixture on success or failure, preserving
images and all unrelated resources. It does not run Composer scripts or application migrations.

The helper uses a private `:Z` bind label for its disposable fixture so Docker can relabel it on SELinux hosts.
Only the newly created fixture is relabeled; do not apply this option to system directories or shared application
checkouts. See Docker's [SELinux bind-mount guidance](https://docs.docker.com/engine/storage/bind-mounts/#configure-the-selinux-label).

Local image builds use the public image targets:

```bash
docker buildx bake image-8-5-dev --load
bash skills/yii2-docker-environment/scripts/validate.sh ghcr.io/yii2-extensions/apache:8.5-debian-dev
```

The CI build workflow builds images; maintainer regression tests are private and run separately. Image builds
may download dependencies. Avoid the `digest-*` Bake targets for local validation: they push to the registry.

## Test an application

Install the application's locked dependencies, including its development tools, before running its own test
command. The image does not include PHPUnit, Codeception, a database server or a default test suite. From the
quick-start container, when the application actually defines the `tests` Composer script:

```bash
docker exec -e COMPOSER_HOME=/tmp/app-composer app composer install --no-interaction --prefer-dist
docker exec app composer run tests
```

For an application with PHPUnit installed at `vendor/bin/phpunit`, use `dev` or `full` for Xdebug coverage:

```bash
docker exec -e XDEBUG_MODE=coverage app php vendor/bin/phpunit --coverage-text
```

`XDEBUG_MODE=off` avoids debugger overhead for ordinary test runs. Configure dedicated test database credentials
and application state before tests that write data. `YII_ENV=test` enables entrypoint service waiting and skips
startup migrations; it does not select or isolate a database for your test suite.

Record the image tag/digest, architecture, user, commands, assertions and any skipped checks. Read
[configuration](configuration.md) when web and CLI PHP settings differ, and [agent setup](agents.md) for skill
installation and activation checks.

[Back to documentation](../README.md#documentation)
