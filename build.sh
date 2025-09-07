#!/bin/bash
set -e

#==============================================================================
# Build Script for Yii2 Docker Images
#==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PHP_VERSION=${PHP_VERSION:-8.4}
BUILD_TYPE=${1:-dev}
DOCKERFILE=${2:-src/flavor/apache/Dockerfile.apache}
IMAGE_PREFIX=${IMAGE_PREFIX:-yii2}

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Validate build type
case $BUILD_TYPE in
    dev|prod|full)
        log_info "Building: $BUILD_TYPE"
        ;;
    *)
        log_error "Invalid BUILD_TYPE: $BUILD_TYPE (use: dev, prod, or full)"
        ;;
esac

# Check Docker
command -v docker >/dev/null 2>&1 || log_error "Docker is not installed"

# Check Dockerfile exists
[[ -f "$DOCKERFILE" ]] || log_error "Dockerfile not found: $DOCKERFILE"

# Create required directories
log_info "Creating directory structure..."
mkdir -p \
    app/web \
    runtime \
    web/assets

# Build image
IMAGE_TAG="${IMAGE_PREFIX}:${PHP_VERSION}-${BUILD_TYPE}"
log_info "Building Docker image: $IMAGE_TAG"

docker build \
    --build-arg PHP_VERSION="${PHP_VERSION}" \
    --build-arg BUILD_TYPE="${BUILD_TYPE}" \
    --tag "${IMAGE_TAG}" \
    --file "${DOCKERFILE}" \
    . || log_error "Docker build failed"

log_success "Image built successfully: $IMAGE_TAG"

# Show image info
echo ""
docker images | grep -E "REPOSITORY|${IMAGE_TAG}"

# Usage instructions
echo ""
log_info "Run with:"
echo -e "${GREEN}docker run -p 8080:80 -v ./app:/var/www/app ${IMAGE_TAG}${NC}"
echo ""
log_info "Or with docker-compose:"
echo -e "${GREEN}docker compose up ${BUILD_TYPE}${NC}"
