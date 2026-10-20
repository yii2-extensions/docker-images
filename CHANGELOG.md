# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v2.3.0 Under development

- docs: use the shared Composer bootstrap and retain optional repository/manual skill installation.

## v2.2.0 October 16, 2026

- docs: enhance `README.md` with comprehensive documentation and AI assistance guides.
- docs/fix: clarify image provenance and document roots; preserve Apache cookies, errors, caching, HTTPS/CSP and routing; lint CI helpers.
- fix: keep Apache access logs valid JSON for UTF-8, invalid bytes, empty users and literal escapes using a native encoder.

## v2.1.0 October 15, 2026

- feat(skills): add an isolated Docker environment skill and document image setup, configuration, debugging and testing.

## v2.0.0 October 6, 2026

- feat!: rebuild the images with `docker buildx bake`, ship them slimmer, and add `install-extensions`, smoke tests and a new Apache setup.

## v1.1.0 January 22, 2026

- feat: update to PHP `8.5`.
- fix: build `sqlsrv/pdo_sqlsrv` in the full image on PHP `8.5` using `BuildKit-mounted` scripts.

## v1.0.0 September 13, 2025

- feat: add Apache, PHP `8.4`, PHP-FPM, and HTTP/2 support, image for Debian Trixie.
