# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v2.1.0 Under development

## v2.0.0 October 6, 2026

- feat!: rebuild the images with `docker buildx bake`, ship them slimmer, and add `install-extensions`, smoke tests and a new Apache setup.

## v1.1.0 January 22, 2026

- feat: update to PHP `8.5`.
- fix: build `sqlsrv/pdo_sqlsrv` in the full image on PHP `8.5` using `BuildKit-mounted` scripts.

## v1.0.0 September 13, 2025

- feat: add Apache, PHP `8.4`, PHP-FPM, and HTTP/2 support, image for Debian Trixie.
