#!/bin/bash
set -euo pipefail

#==============================================================================
# Build Script for Yii2 Docker Images
#==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PHP_VERSION=${PHP_VERSION:-8.4}
BUILD_TYPE=${1:-dev}
DOCKERFILE=${DOCKERFILE:-./src/flavor/apache/Dockerfile.apache}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "$DOCKERFILE" ]; then
    print_error "Dockerfile not found: $DOCKERFILE"
    print_info "Please run this script from the project root directory"
    exit 1
fi

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

# Validate build type
case $BUILD_TYPE in
    dev|prod|full)
        print_info "Building variant: $BUILD_TYPE"
        ;;
    *)
        print_error "Invalid BUILD_TYPE: $BUILD_TYPE"
        print_info "Valid options are: dev, prod, full"
        exit 1
        ;;
esac

# Create necessary directories if they don't exist
print_info "Creating directory structure..."
mkdir -p app/web
mkdir -p app/web/assets
mkdir -p runtime

# Check for required configuration files
REQUIRED_FILES=(
    "src/flavor/apache/etc/apache2.conf"
    "src/flavor/apache/etc/vhost.conf"
    "src/php/${BUILD_TYPE}.ini"
    "src/script/entrypoint.sh"
)

if [ "$BUILD_TYPE" = "full" ]; then
    REQUIRED_FILES+=(
        "src/script/install-oracle.sh"
        "src/script/install-mssql.sh"
    )
fi

if [ "$BUILD_TYPE" = "dev" ] || [ "$BUILD_TYPE" = "full" ]; then
    REQUIRED_FILES+=("src/php/xdebug.ini")
fi

# Check for missing files
MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    print_warning "Missing configuration files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    print_info "Creating dummy files for missing configurations..."
    for file in "${MISSING_FILES[@]}"; do
        mkdir -p "$(dirname "$file")"
        touch "$file"
        print_info "Created: $file"
    done
fi

# Build the Docker image
IMAGE_TAG="yii2-apache:${PHP_VERSION}-debian-${BUILD_TYPE}"
print_info "Building Docker image: $IMAGE_TAG"
print_info "PHP Version: $PHP_VERSION"
print_info "Build Type: $BUILD_TYPE"

# Build command with proper arguments
docker build \
    --build-arg PHP_VERSION="${PHP_VERSION}" \
    --build-arg BUILD_TYPE="${BUILD_TYPE}" \
    --tag "${IMAGE_TAG}" \
    --file "${DOCKERFILE}" \
    .

if [ $? -eq 0 ]; then
    print_success "Docker image built successfully: $IMAGE_TAG"

    # Show image info
    echo ""
    print_info "Image details:"
    docker images | grep -E "REPOSITORY|${IMAGE_TAG}"

    echo ""
    print_info "To run the container:"
    echo -e "${GREEN}docker run -p 8080:80 -v ./app:/var/www/app ${IMAGE_TAG}${NC}"

    echo ""
    print_info "To run with docker-compose:"
    echo -e "${GREEN}docker compose up -d yii2-${BUILD_TYPE}${NC}"
else
    print_error "Docker build failed"
    exit 1
fi

# Optional: Run tests for the built image
if [ "$2" = "--test" ]; then
    print_info "Running basic tests..."

    # Start a test container
    CONTAINER_NAME="yii2-test-${BUILD_TYPE}"
    docker run -d --name "${CONTAINER_NAME}" "${IMAGE_TAG}"

    # Wait for container to be ready
    sleep 5

    # Check PHP version
    print_info "Checking PHP version..."
    docker exec "${CONTAINER_NAME}" php -v | grep "PHP ${PHP_VERSION}"

    # Check installed extensions
    print_info "Checking PHP extensions..."
    docker exec "${CONTAINER_NAME}" php -m | grep -E "pdo|intl|mbstring|opcache"

    # Additional checks for full build
    if [ "$BUILD_TYPE" = "full" ]; then
        print_info "Checking Oracle and MSSQL extensions..."
        docker exec "${CONTAINER_NAME}" php -m | grep -E "oci8|sqlsrv" || print_warning "Oracle/MSSQL extensions not found"
    fi

    # Clean up test container
    docker stop "${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}"

    print_success "Tests completed"
fi
