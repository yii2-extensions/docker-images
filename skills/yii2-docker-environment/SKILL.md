---
name: yii2-docker-environment
description: Set up or validate a local Yii application environment using yii2-extensions/docker-images, including image selection, UID permissions, HTTP/HTTPS checks, debugging and isolated cleanup. Use for these container images, not PHP extension installation or image publication.
license: BSD-3-Clause
metadata:
  guide: https://github.com/yii2-extensions/docker-images/tree/72c2a0e2d7d7ed862f6fa4d441d8c124684d3e05/docs
---

# Run and validate a Yii Docker environment

Use the application's instructions and actual PHP/Composer constraints. These are Apache/PHP-FPM images, not a Yii
installer or Composer package. Do not change Dockerfiles, daemon configuration or release workflows just to make a
local validation pass.

## Consult the canonical guides

When a source checkout is available, read its `README.md` and only the relevant `docs/` page. Otherwise use these
available package guides, pinned to a verified revision with the helper's daemon requirements:

- Requirements, tags, setup: <https://raw.githubusercontent.com/yii2-extensions/docker-images/72c2a0e2d7d7ed862f6fa4d441d8c124684d3e05/docs/installation.md>.
- Startup flags, permissions, FPM and Xdebug: <https://raw.githubusercontent.com/yii2-extensions/docker-images/72c2a0e2d7d7ed862f6fa4d441d8c124684d3e05/docs/configuration.md>.
- Mounts, console commands, diagnostics: <https://raw.githubusercontent.com/yii2-extensions/docker-images/72c2a0e2d7d7ed862f6fa4d441d8c124684d3e05/docs/examples.md>.
- Stack versus application checks: <https://raw.githubusercontent.com/yii2-extensions/docker-images/72c2a0e2d7d7ed862f6fa4d441d8c124684d3e05/docs/testing.md>.

For another installed or requested revision, use its `docs/` at that revision on GitHub. Switch to the
documentation site's Markdown URLs only after verifying that those pages are published. Do not substitute another
Yii Docker project's tags or configuration.

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
