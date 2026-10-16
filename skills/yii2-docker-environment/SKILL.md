---
name: yii2-docker-environment
description: Set up or validate a local Yii application environment using yii2-extensions/docker-images, including image selection, UID permissions, HTTP/HTTPS checks, debugging and isolated cleanup. Use for these container images, not PHP extension installation or image publication.
license: BSD-3-Clause
metadata:
  guide: https://github.com/yii2-extensions/docker-images
---

# Run and validate a Yii Docker environment

Use the application's instructions and actual PHP/Composer constraints. These are Apache/PHP-FPM images, not a Yii
installer or Composer package. Do not change Dockerfiles, daemon configuration or release workflows just to make a
local validation pass.

## Consult the canonical guides

Identify the image actually used by the container, or the selected local image, with Docker inspect. Record its
image ID, registry digest when available, platform and tag. Tags can move; an image digest is not a Git commit.
Use verified build provenance or `org.opencontainers.image.revision` to locate matching source documentation in
<https://github.com/yii2-extensions/docker-images>. If no source revision can be established, report that gap.
When the task targets a source checkout, inspect its current `HEAD` and files even when clean. Uncommitted
files have no matching SHA; the checkout alone does not establish the running image's source revision.

Read the matching `README.md` and only the relevant guide:

- `docs/installation.md`: requirements, tags, setup.
- `docs/configuration.md`: startup flags, permissions, FPM and Xdebug.
- `docs/examples.md`: mounts, console commands, diagnostics.
- `docs/testing.md`: stack versus application checks.

Use hosted pages or snapshots only when their source revision matches. If matching guides are unavailable or
offline, inspect available local guides, Dockerfiles, scripts and image configuration, and state the limits.
Do not substitute another Yii Docker project's tags or configuration.

## Select and prepare

1. Check `docker info`, daemon locality and the host architecture. The fixture helper requires rootful Docker without user-namespace remapping; report unsupported modes without changing daemon configuration or permissions. Compose is optional; Buildx is needed for Bake builds only.
2. Inspect the requested registry manifest before pulling a new tag. Match the application's PHP constraints and required tools to the README variant table. Experimental Bake targets do not imply a published registry tag.
3. Inspect the application's bootstrap, lockfile, mounts and test commands before starting it. Determine what reads `YII_ENV`/`YII_DEBUG`; do not assume environment variables override PHP constants.
4. Use the host UID:GID for Linux bind mounts. Account for hidden image files under a project mount and for the ownership of new named volumes. Avoid root initialization and broad ownership changes on user checkouts.
5. For an application run, choose an exclusive Compose project/container name and loopback ports. Use dedicated test state for data-writing commands. Disable automatic Composer, migrations and service waits for fixture-only checks.

## Validate with evidence

For a stack check without application dependencies, use the bundled helper after pulling the selected image:

```bash
bash <skill-directory>/scripts/validate.sh <verified-local-image>
```

It requires Bash, Docker, curl, Python 3, a non-root host user and a local rootful Linux daemon without
user-namespace remapping. It rejects unsupported daemon modes before creating resources. It creates a temporary PHP
fixture with a private SELinux `:Z` bind label, publishes dynamic loopback ports and removes its own resources on
exit. It never pulls or builds an image.
Inspect the helper if adapting the assertions. It tests the stable image defaults, not an arbitrary derived image.

For an actual application, follow the usage and testing guides: request an application route as well as `/health`,
verify writable state, then run only the application's defined checks. `/health` can pass without a working Yii
application or database. `PHP_*` pool settings need a Web request check; CLI PHP has its own INI. Xdebug coverage
requires `dev`/`full` plus the application's test runner. Separate direct helper results from native skill activation.

## Clean up and report

Track every resource created for the task. Stop and remove only those containers and any explicitly disposable
volumes/networks you created. Preserve images, dependency caches and unrelated resources; never use `prune` or bulk
removal. On failure, capture relevant logs and inspect the cause before cleanup; do not run unrestricted retries.
Report the image ID/digest, platform, user, endpoints and assertions, application checks performed or skipped, and
remaining prerequisites. Do not publish images or deploy services as part of this workflow.
