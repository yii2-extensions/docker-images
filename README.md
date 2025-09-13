<!-- markdownlint-disable MD041 -->
<p align="center">
    <a href="https://github.com/yii2-extensions/docker-images" target="_blank">
        <img src="https://www.yiiframework.com/image/yii_logo_light.svg" alt="Yii Framework">
    </a>
    <h1 align="center">Docker images</h1>
    <br>
</p>
<!-- markdownlint-enable MD041 -->

Production-ready Docker images for Yii2 applications with Apache, PHP-FPM, and HTTP/2 support.

## Features

- ✅ **Apache 2.4** with HTTP/2, Brotli compression, and SSL/TLS
- ✅ **Auto SSL** certificate generation for development
- ✅ **Health checks** and monitoring endpoints
- ✅ **PHP 8.4** with FPM and essential extensions (Redis, MongoDB, MySQL, PostgreSQL)
- ✅ **Security hardened** with modern configurations
- ✅ **Supervisor** for process management
- ✅ **Three build variants**: `dev`, `prod`, and `full`

### Quick Start

Pull and run the image.

```bash
# Development build with Xdebug
docker run -d -p 8080:80 -v $(pwd):/var/www/app ghcr.io/yii2-extensions/apache:8.4-debian-dev-v1.0.0

# Production build with optimizations
docker run -d -p 80:80 -p 443:443 -v $(pwd):/var/www/app ghcr.io/yii2-extensions/apache:8.4-debian-prod-v1.0.0

# Full testing build with all extensions
docker run -d -p 8080:80 -v $(pwd):/var/www/app ghcr.io/yii2-extensions/apache:8.4-debian-full-v1.0.0
```

### Docker Compose

Create a `docker-compose.yml` file.

<!-- editorconfig-checker-disable -->
<!-- prettier-ignore-start -->
```yaml
version: '3.8'

services:
  web:
    image: ghcr.io/yii2-extensions/apache:8.4-debian-dev-v1.0.0
    ports:
      - "8080:80"
      - "8443:443"
    volumes:
      - .:/var/www/app
    environment:
      - YII_ENV=dev
      - YII_DEBUG=1
```
<!-- prettier-ignore-end -->
<!-- editorconfig-checker-enable -->

### Build Variants

#### Development (`dev`)

```bash
docker pull ghcr.io/yii2-extensions/apache:8.4-debian-dev-v1.0.0
```

- Error reporting enabled with detailed logging
- Node.js integration for asset compilation
- OPcache with revalidation for development workflow
- PHP `8.4` with Xdebug, Memcached, MongoDB, SOAP, YAML

#### Production (`prod`)

```bash
docker pull ghcr.io/yii2-extensions/apache:8.4-debian-prod-v1.0.0
```

- Minimal extension set with maximum performance
- OPcache optimizations with disabled timestamp validation
- Optimized for container orchestration platforms
- Security hardening with reduced attack surface

#### Full Testing (`full`)

```bash
docker pull ghcr.io/yii2-extensions/apache:8.4-debian-full-v1.0.0
```

- All development extensions plus OCI8, SQL Server, Tidy
- Complete extension matrix for comprehensive testing
- Microsoft SQL Server ODBC drivers and PDO support
- Production-like optimizations with development tools

## Package information

[![Docker Build](https://img.shields.io/github/actions/workflow/status/yii2-extensions/docker-images/build.yml?style=for-the-badge&logo=docker&logoColor=white&label=Docker%20Build)](https://github.com/yii2-extensions/docker-images/actions/workflows/build.yml)
[![GitHub Release](https://img.shields.io/github/v/release/yii2-extensions/docker-images?style=for-the-badge&logo=git&logoColor=white&label=Release)](https://github.com/yii2-extensions/docker-images/releases)

## Quality code

[![Super-Linter](https://img.shields.io/github/actions/workflow/status/yii2-extensions/docker-images/linter.yml?style=for-the-badge&label=Super-Linter&logo=github)](https://github.com/yii2-extensions/docker-images/actions/workflows/linter.yml)

## Our social networks

[![Follow on X](https://img.shields.io/badge/-Follow%20on%20X-1DA1F2.svg?style=for-the-badge&logo=x&logoColor=white&labelColor=000000)](https://x.com/Terabytesoftw)

## License

[![License](https://img.shields.io/badge/License-BSD--3--Clause-brightgreen.svg?style=for-the-badge&logo=opensourceinitiative&logoColor=white&labelColor=555555)](LICENSE)
