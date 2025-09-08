#==============================================================================
# SSL setup for Apache with HTTP/2 support
#==============================================================================

# Load logging functions from system
source /usr/local/bin/common/10-log.sh

# SSL configuration
SSL_DIR="/etc/apache2/ssl"
SSL_CERT="${SSL_DIR}/cert.pem"
SSL_KEY="${SSL_DIR}/key.pem"

# Create SSL directory
if [[ ! -d "$SSL_DIR" ]]; then
    log INFO "Creating SSL directory: $SSL_DIR"
    mkdir -p "$SSL_DIR"
    chown www-data:www-data "$SSL_DIR"
    chmod 755 "$SSL_DIR"
fi

# Generate SSL certificates if they don't exist
if [[ ! -f "$SSL_CERT" ]] || [[ ! -f "$SSL_KEY" ]]; then
    log INFO "Generating self-signed SSL certificates for HTTP/2..."

    # Generate private key
    if ! openssl genrsa -out "$SSL_KEY" 2048 2>/dev/null; then
        log WARNING "Failed to generate private key, SSL will be disabled"
        return 0 2>/dev/null || exit 0
    fi

    # Generate self-signed certificate (simplified for compatibility)
    if ! openssl req -new -x509 -key "$SSL_KEY" -out "$SSL_CERT" -days 365 \
        -subj "/C=US/ST=State/L=City/O=Yii2Docker/OU=Development/CN=localhost" \
        2>/dev/null; then
        log WARNING "Failed to generate certificate, SSL will be disabled"
        rm -f "$SSL_KEY" 2>/dev/null || true
        return 0 2>/dev/null || exit 0
    fi

    # Set proper permissions
    chmod 644 "$SSL_CERT" 2>/dev/null || true
    chmod 600 "$SSL_KEY" 2>/dev/null || true
    chown www-data:www-data "$SSL_CERT" "$SSL_KEY" 2>/dev/null || true

    log SUCCESS "SSL certificates generated successfully"
    log INFO "Certificate: $SSL_CERT"
    log INFO "Private key: $SSL_KEY"
else
    log INFO "SSL certificates already exist"
fi

# Verify certificates
if [[ -f "$SSL_CERT" ]] && openssl x509 -in "$SSL_CERT" -text -noout >/dev/null 2>&1; then
    CERT_SUBJECT=$(openssl x509 -in "$SSL_CERT" -subject -noout 2>/dev/null | sed 's/subject= *//' || echo "Unknown")
    CERT_EXPIRES=$(openssl x509 -in "$SSL_CERT" -enddate -noout 2>/dev/null | sed 's/notAfter=//' || echo "Unknown")
    log INFO "Certificate subject: $CERT_SUBJECT"
    log INFO "Certificate expires: $CERT_EXPIRES"
else
    log WARNING "SSL certificate verification failed or certificate not found"
fi

# Create cache directories for SSL
mkdir -p /var/cache/apache2
chown www-data:www-data /var/cache/apache2
chmod 755 /var/cache/apache2

log INFO "SSL setup completed"
