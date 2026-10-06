#==============================================================================
# Yii2 Docker - Build definition for docker buildx bake
#
# Target families (matrix over PHP version x variant, dot replaced by dash):
#   image-<php>-<variant>   tagged image, Dockerfile target "final"
#   smoke-<php>-<variant>   runs tests/smoke.sh inside the image, no output
#   digest-<php>-<variant>  untagged image pushed by digest (CI manifest merge)
#
# Examples:
#   docker buildx bake                               # stable image-* targets
#   docker buildx bake image-8-5-prod --load         # one image into the local store
#   docker buildx bake --print image                 # every image-* target as JSON
#==============================================================================

# Image repository the tags are generated for.
variable "IMAGE" {
  default = "ghcr.io/yii2-extensions/apache"
}

# Release version without the leading "v"; adds the "-v<VERSION>" tags when set.
variable "VERSION" {
  default = ""
}

# PHP version whose "prod" variant also receives the "latest" tag.
variable "LATEST_PHP" {
  default = "8.5"
}

# OCI "created" label (RFC 3339 date-time); omitted when empty.
variable "CREATED" {
  default = ""
}

# OCI "revision" label (VCS commit); omitted when empty.
variable "REVISION" {
  default = ""
}

# Supported PHP versions. "base" is the tag prefix of the upstream php image; a version whose "base" differs from
# "version" (a release candidate) is experimental and is excluded from the "default" group. "args" holds optional
# per-version build arguments, such as reduced extension lists for versions the extensions do not support yet.
variable "PHP" {
  default = [
    { version = "8.3", base = "8.3", args = {} },
    { version = "8.4", base = "8.4", args = {} },
    { version = "8.5", base = "8.5", args = {} },
    # php-extension-installer 2.12.0 has no PHP 8.6 data: PECL builds fall back to pickle, which needs mbstring
    # (absent from php:8.6-rc and not installable by the installer there), and gd loses libwebpdemux at cleanup.
    {
      version = "8.6",
      base    = "8.6-rc",
      args = {
        PHP_EXTENSIONS_PROD = "@composer bcmath intl opcache pcntl pdo_mysql pdo_pgsql zip"
        PHP_EXTENSIONS_DEV  = "soap"
        PHP_EXTENSIONS_FULL = "tidy"
      }
    },
  ]
}

# Image variants, from smallest to largest.
variable "VARIANTS" {
  default = ["prod", "dev", "full"]
}

# Build settings shared by every target.
target "_common" {
  context    = "."
  dockerfile = "src/flavor/apache/Dockerfile"
  labels = {
    for key, value in {
      "org.opencontainers.image.created"  = CREATED
      "org.opencontainers.image.revision" = REVISION
      "org.opencontainers.image.version"  = VERSION
    } : key => value if value != ""
  }
}

# Tagged images.
target "image" {
  inherits = ["_common"]
  name     = "image-${replace(php.version, ".", "-")}-${variant}"
  matrix = {
    php     = PHP
    variant = VARIANTS
  }
  target = "final"
  args = merge(
    {
      BUILD_TYPE   = variant
      PHP_VERSION  = php.version
      PHP_BASE_TAG = php.base
    },
    php.args,
  )
  tags = concat(
    ["${IMAGE}:${php.version}-debian-${variant}"],
    VERSION != "" ? ["${IMAGE}:${php.version}-debian-${variant}-v${VERSION}"] : [],
    php.version == LATEST_PHP && variant == "prod" ? ["${IMAGE}:latest"] : [],
  )
}

# Smoke tests: build the "smoke" stage only, keep the result in the build cache.
target "smoke" {
  inherits = ["_common"]
  name     = "smoke-${replace(php.version, ".", "-")}-${variant}"
  matrix = {
    php     = PHP
    variant = VARIANTS
  }
  target = "smoke"
  args = merge(
    {
      BUILD_TYPE   = variant
      PHP_VERSION  = php.version
      PHP_BASE_TAG = php.base
    },
    php.args,
  )
  output = ["type=cacheonly"]
}

# Per-architecture images pushed by digest, merged into a manifest list by CI.
target "digest" {
  inherits = ["_common"]
  name     = "digest-${replace(php.version, ".", "-")}-${variant}"
  matrix = {
    php     = PHP
    variant = VARIANTS
  }
  target = "final"
  args = merge(
    {
      BUILD_TYPE   = variant
      PHP_VERSION  = php.version
      PHP_BASE_TAG = php.base
    },
    php.args,
  )
  output = ["type=image,name=${IMAGE},push-by-digest=true,name-canonical=true,push=true"]
}

# Stable images only; experimental versions are built by naming their targets explicitly.
group "default" {
  targets = flatten([
    for php in PHP : [
      for variant in VARIANTS : "image-${replace(php.version, ".", "-")}-${variant}"
    ] if php.base == php.version
  ])
}
