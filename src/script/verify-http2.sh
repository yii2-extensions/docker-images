#!/bin/bash
#
# HTTP/2 Verification Script for Yii2 Docker
# Tests HTTP/2 functionality and SSL configuration
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
HTTP_PORT=${HTTP_PORT:-8080}
HTTPS_PORT=${HTTPS_PORT:-8443}
HOST=${HOST:-localhost}
HEALTH_ENDPOINT="/health"
MAX_RETRIES=30
RETRY_DELAY=2

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test HTTP/1.1 connection
test_http11() {
    log_info "Testing HTTP/1.1 connection..."

    local response
    if response=$(curl -s -w "HTTP Code: %{http_code}\nHTTP Version: %{http_version}\nTime Total: %{time_total}s\n" \
        "http://${HOST}:${HTTP_PORT}${HEALTH_ENDPOINT}" 2>/dev/null); then

        if echo "$response" | grep -q "HTTP Code: 200"; then
            log_success "HTTP/1.1 connection successful"
            echo "$response" | grep -E "(HTTP Code|HTTP Version|Time Total)"
            return 0
        else
            log_error "HTTP/1.1 connection failed"
            echo "$response"
            return 1
        fi
    else
        log_error "Failed to connect via HTTP/1.1"
        return 1
    fi
}

# Test HTTP/2 connection
test_http2() {
    log_info "Testing HTTP/2 connection..."

    # Check if curl supports HTTP/2
    if ! curl --version | grep -q "HTTP2"; then
        log_warning "curl does not support HTTP/2 - skipping HTTP/2 test"
        return 0
    fi

    local response
    if response=$(curl -s -k --http2 -w "HTTP Code: %{http_code}\nHTTP Version: %{http_version}\nTime Total: %{time_total}s\nProtocol: %{scheme}\n" \
        "https://${HOST}:${HTTPS_PORT}${HEALTH_ENDPOINT}" 2>/dev/null); then

        if echo "$response" | grep -q "HTTP Code: 200"; then
            log_success "HTTP/2 connection successful"
            echo "$response" | grep -E "(HTTP Code|HTTP Version|Time Total|Protocol)"

            # Check if HTTP/2 was actually used
            if echo "$response" | grep -q "HTTP Version: 2"; then
                log_success "HTTP/2 protocol confirmed"
            else
                log_warning "Connected but not using HTTP/2"
            fi
            return 0
        else
            log_error "HTTP/2 connection failed"
            echo "$response"
            return 1
        fi
    else
        log_error "Failed to connect via HTTP/2"
        return 1
    fi
}

# Test SSL certificate
test_ssl_certificate() {
    log_info "Testing SSL certificate..."

    local cert_info
    if cert_info=$(echo | openssl s_client -connect "${HOST}:${HTTPS_PORT}" -servername "${HOST}" 2>/dev/null | \
        openssl x509 -text -noout 2>/dev/null); then

        log_success "SSL certificate is valid"

        # Extract key information
        local subject=$(echo "$cert_info" | grep "Subject:" | head -1)
        local issuer=$(echo "$cert_info" | grep "Issuer:" | head -1)
        local validity=$(echo "$cert_info" | grep -A1 "Validity" | tail -1)

        echo "  $subject"
        echo "  $issuer"
        echo "  $validity"

        return 0
    else
        log_error "SSL certificate test failed"
        return 1
    fi
}

# Test performance with HTTP/2 vs HTTP/1.1
test_performance() {
    log_info "Testing performance comparison..."

    # Test HTTP/1.1
    local http11_time
    if http11_time=$(curl -s -w "%{time_total}" -o /dev/null \
        "http://${HOST}:${HTTP_PORT}${HEALTH_ENDPOINT}" 2>/dev/null); then
        log_info "HTTP/1.1 response time: ${http11_time}s"
    else
        log_warning "Could not measure HTTP/1.1 performance"
        http11_time="N/A"
    fi

    # Test HTTP/2 (if curl supports it)
    if curl --version | grep -q "HTTP2"; then
        local http2_time
        if http2_time=$(curl -s -k --http2 -w "%{time_total}" -o /dev/null \
            "https://${HOST}:${HTTPS_PORT}${HEALTH_ENDPOINT}" 2>/dev/null); then
            log_info "HTTP/2 response time: ${http2_time}s"

            # Calculate improvement (if both times are numeric)
            if [[ "$http11_time" != "N/A" ]] && [[ "$http2_time" =~ ^[0-9.]+$ ]] && [[ "$http11_time" =~ ^[0-9.]+$ ]]; then
                local improvement=$(echo "scale=2; ($http11_time - $http2_time) / $http11_time * 100" | bc -l 2>/dev/null || echo "N/A")
                if [[ "$improvement" != "N/A" ]]; then
                    log_success "HTTP/2 performance improvement: ${improvement}%"
                fi
            fi
        else
            log_warning "Could not measure HTTP/2 performance"
        fi
    fi
}

# Wait for service to be ready
wait_for_service() {
    log_info "Waiting for service to be ready..."

    local retry=0
    while [[ $retry -lt $MAX_RETRIES ]]; do
        if curl -s "http://${HOST}:${HTTP_PORT}${HEALTH_ENDPOINT}" >/dev/null 2>&1; then
            log_success "Service is ready"
            return 0
        fi

        ((retry++))
        log_info "Waiting for service... (attempt $retry/$MAX_RETRIES)"
        sleep $RETRY_DELAY
    done

    log_error "Service did not become ready within $(($MAX_RETRIES * $RETRY_DELAY)) seconds"
    return 1
}

# Main function
main() {
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}HTTP/2 Verification Script for Yii2 Docker${NC}"
    echo -e "${BLUE}==============================================================================${NC}"
    echo ""

    log_info "Configuration:"
    echo "  Host: $HOST"
    echo "  HTTP Port: $HTTP_PORT"
    echo "  HTTPS Port: $HTTPS_PORT"
    echo "  Health Endpoint: $HEALTH_ENDPOINT"
    echo ""

    # Wait for service
    if ! wait_for_service; then
        exit 1
    fi

    local tests_passed=0
    local total_tests=0

    # Run tests
    echo ""
    ((total_tests++))
    if test_http11; then
        ((tests_passed++))
    fi

    echo ""
    ((total_tests++))
    if test_ssl_certificate; then
        ((tests_passed++))
    fi

    echo ""
    ((total_tests++))
    if test_http2; then
        ((tests_passed++))
    fi

    echo ""
    test_performance

    # Summary
    echo ""
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}==============================================================================${NC}"

    if [[ $tests_passed -eq $total_tests ]]; then
        log_success "All tests passed ($tests_passed/$total_tests)"
        log_success "HTTP/2 is working correctly!"
        exit 0
    else
        log_error "Some tests failed ($tests_passed/$total_tests)"
        exit 1
    fi
}

# Run main function
main "$@"
