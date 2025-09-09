#==============================================================================
# SSL setup for Apache with HTTP/2 support
#==============================================================================

# Load logging functions from system
source /usr/local/bin/common/10-log.sh

# Check if SSL is disabled
if [[ "${SSL_ENABLED:-true}" != "true" ]]; then
    log INFO "SSL is disabled via SSL_ENABLED=false"

    return 0 2>/dev/null || exit 0
fi

# SSL configuration - use environment variables or defaults
SSL_DIR="${SSL_DIR:-/etc/apache2/ssl}"
SSL_CERT_FILE="${SSL_CERT_FILE:-${SSL_DIR}/cert.pem}"
SSL_KEY_FILE="${SSL_KEY_FILE:-${SSL_DIR}/key.pem}"
SSL_AUTO_GENERATE="${SSL_AUTO_GENERATE:-true}"

# Enable SSL in Apache (append to existing APACHE_ARGUMENTS)
echo "export APACHE_ARGUMENTS=\"\${APACHE_ARGUMENTS} -D SSL_ENABLED\"" >> /etc/apache2/envvars

# Optional: Enable HTTP to HTTPS redirect
if [[ "${SSL_REDIRECT:-false}" == "true" ]]; then
    echo "export APACHE_ARGUMENTS=\"\${APACHE_ARGUMENTS} -D SSL_REDIRECT\"" >> /etc/apache2/envvars
fi

# Create SSL directory
if [[ ! -d "$SSL_DIR" ]]; then
    log INFO "Creating SSL directory: $SSL_DIR"

    mkdir -p "$SSL_DIR"
    chown www-data:www-data "$SSL_DIR"
    chmod 755 "$SSL_DIR"
fi

# Check if external certificates are provided
if [[ -f "$SSL_CERT_FILE" ]] && [[ -f "$SSL_KEY_FILE" ]]; then
    log INFO "SSL certificates found at configured paths"

    CERT_SUBJECT=$(openssl x509 -in "$SSL_CERT_FILE" -subject -noout 2>/dev/null | sed 's/subject= *//' || echo "Unknown")
    CERT_EXPIRES=$(openssl x509 -in "$SSL_CERT_FILE" -enddate -noout 2>/dev/null | sed 's/notAfter=//' || echo "Unknown")

    log INFO "Certificate subject: $CERT_SUBJECT"
    log INFO "Certificate expires: $CERT_EXPIRES"

    # Update Apache configuration with the certificate paths
    if [[ -f /etc/apache2/sites-available/yii2.conf ]]; then
        sed -i "s|SSLCertificateFile .*|SSLCertificateFile ${SSL_CERT_FILE}|g" /etc/apache2/sites-available/yii2.conf
        sed -i "s|SSLCertificateKeyFile .*|SSLCertificateKeyFile ${SSL_KEY_FILE}|g" /etc/apache2/sites-available/yii2.conf

        # Add chain certificate if provided
        if [[ -n "${SSL_CHAIN_FILE:-}" ]] && [[ -f "$SSL_CHAIN_FILE" ]]; then
            if ! grep -q "SSLCertificateChainFile" /etc/apache2/sites-available/yii2.conf; then
                sed -i "/SSLCertificateKeyFile/a\    SSLCertificateChainFile ${SSL_CHAIN_FILE}" /etc/apache2/sites-available/yii2.conf
            else
                sed -i "s|SSLCertificateChainFile .*|SSLCertificateChainFile ${SSL_CHAIN_FILE}|g" /etc/apache2/sites-available/yii2.conf
            fi
        fi
    fi

elif [[ "$SSL_AUTO_GENERATE" == "true" ]]; then
    # DISABLE_OCSP stapling for self-signed certificates unless explicitly enabled
    local DISABLE_OCSP="${DISABLE_OCSP_STAPLING:-true}"
    # Set SSL_CONFIG path
    local SSL_CONFIG="${SSL_DIR}/openssl.conf"

    # Set DISABLE_OCSP based on environment variables
    if [[ "$DISABLE_OCSP" == "true" ]]; then
        echo "export APACHE_ARGUMENTS=\"\${APACHE_ARGUMENTS} -D DISABLE_OCSP_STAPLING\"" >> /etc/apache2/envvars

        log INFO "OCSP stapling disabled for self-signed certificate"
    fi

    # Generate self-signed certificates if they don't exist
    log INFO "Generating self-signed SSL certificates for HTTP/2..."

    # Generate private key
    if ! openssl genrsa -out "$SSL_KEY_FILE" 2048 2>/dev/null; then
        log WARNING "Failed to generate private key, SSL will be disabled"

        return 0 2>/dev/null || exit 0
    fi

    # Generate self-signed certificate
    if ! openssl req -new -x509 -key "$SSL_KEY_FILE" -out "$SSL_CERT_FILE" -days 365 \
        -config "$SSL_CONFIG" -extensions v3_req \
        2>/dev/null; then

        log WARNING "Failed to generate certificate, SSL will be disabled"

        rm -f "$SSL_KEY_FILE" "$SSL_CONFIG" 2>/dev/null || true

        return 0 2>/dev/null || exit 0
    fi

    # Set proper permissions
    chmod 644 "$SSL_CERT_FILE" 2>/dev/null || true
    chmod 600 "$SSL_KEY_FILE" 2>/dev/null || true
    chown www-data:www-data "$SSL_CERT_FILE" "$SSL_KEY_FILE" 2>/dev/null || true

    log SUCCESS "SSL certificates generated successfully"
    log INFO "Certificate: $SSL_CERT_FILE"
    log INFO "Private key: $SSL_KEY_FILE"
else
    log WARNING "SSL certificates not found and auto-generation is disabled"
    log INFO "Please mount certificates or set SSL_AUTO_GENERATE=true"

    return 0 2>/dev/null || exit 0
fi

# Create cache directories for SSL
mkdir -p /var/cache/apache2
chown www-data:www-data /var/cache/apache2
chmod 755 /var/cache/apache2

log INFO "SSL setup completed"
