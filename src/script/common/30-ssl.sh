#==============================================================================
# SSL setup for Apache with HTTP/2 support
#==============================================================================

setup_apache_vhost() {
    log INFO "Configuring Apache virtual hosts..."

    # Disable all sites first (silent)
    if [[ -d /etc/apache2/sites-enabled ]]; then
        for conf in /etc/apache2/sites-enabled/*.conf; do
            if [[ -f "$conf" ]]; then
                site=$(basename "$conf" .conf)
                a2dissite "$site" >/dev/null 2>&1
            fi
        done
    fi

    # Check if SSL is disabled
    if [[ "${APACHE_SSL_ENABLED:-true}" != "true" ]]; then
        log INFO "SSL is disabled - enabling HTTP-only configuration"
        if [[ -f /etc/apache2/sites-available/vhost.conf ]]; then
            a2ensite vhost >/dev/null 2>&1
            log SUCCESS "Enabled HTTP-only virtual host"
        else
            log ERROR "vhost.conf not found"
            return 1
        fi
        return 0
    fi

    # SSL is enabled, determine which configuration to use
    if [[ "${APACHE_SSL_REDIRECT:-false}" == "true" ]]; then
        log INFO "Enabling HTTPS with HTTP redirect configuration"
        if [[ -f /etc/apache2/sites-available/vhost-ssl-full.conf ]]; then
            a2ensite vhost-ssl-full >/dev/null 2>&1
            log SUCCESS "Enabled full SSL configuration with redirect"
        else
            log ERROR "vhost-ssl-full.conf not found"
            return 1
        fi
    else
        log INFO "Enabling separate HTTP and HTTPS configurations"
        # Enable both HTTP and HTTPS without redirect
        if [[ -f /etc/apache2/sites-available/vhost.conf ]]; then
            a2ensite vhost >/dev/null 2>&1
            log SUCCESS "Enabled HTTP virtual host"
        else
            log ERROR "vhost.conf not found"
        fi

        if [[ -f /etc/apache2/sites-available/vhost-ssl.conf ]]; then
            a2ensite vhost-ssl >/dev/null 2>&1
            log SUCCESS "Enabled HTTPS virtual host"
        else
            log ERROR "vhost-ssl.conf not found"
        fi
    fi

    # Handle OCSP stapling configuration
    if [[ "${SSL_AUTO_GENERATE:-true}" == "true" ]] || [[ "${APACHE_DISABLE_OCSP_STAPLING:-false}" == "true" ]]; then
        log INFO "Disabling OCSP stapling for self-signed certificates"
        # Comment out OCSP stapling lines in apache2.conf
        sed -i 's/^\s*SSLUseStapling on/    # SSLUseStapling on/' /etc/apache2/apache2.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingCache/    # SSLStaplingCache/' /etc/apache2/apache2.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingResponderTimeout/    # SSLStaplingResponderTimeout/' /etc/apache2/apache2.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingReturnResponderErrors/    # SSLStaplingReturnResponderErrors/' /etc/apache2/apache2.conf 2>/dev/null || true
    else
        log INFO "OCSP stapling enabled (external certificates)"
        # Uncomment OCSP stapling lines if they were previously commented
        sed -i 's/^\s*#\s*SSLUseStapling on/    SSLUseStapling on/' /etc/apache2/apache2.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingCache/    SSLStaplingCache/' /etc/apache2/apache2.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingResponderTimeout/    SSLStaplingResponderTimeout/' /etc/apache2/apache2.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingReturnResponderErrors/    SSLStaplingReturnResponderErrors/' /etc/apache2/apache2.conf 2>/dev/null || true
    fi

    # Re-create only the needed symlinks
    for conf in /etc/apache2/sites-enabled/*.conf; do
        if [[ -L "$conf" ]] && [[ -e "$conf" ]]; then
            log DEBUG "Active site: $(basename "$conf")"
        fi
    done
}

# Main SSL setup logic
main_ssl_setup() {
    # Check if SSL is disabled
    if [[ "${APACHE_SSL_ENABLED:-true}" != "true" ]]; then
        log INFO "SSL is disabled via APACHE_SSL_ENABLED=false"
        setup_apache_vhost
        return 0
    fi

    # SSL configuration - use environment variables or defaults
    SSL_DIR="${SSL_DIR:-/etc/apache2/ssl}"
    SSL_CERT_FILE="${SSL_CERT_FILE:-${SSL_DIR}/cert.pem}"
    SSL_KEY_FILE="${SSL_KEY_FILE:-${SSL_DIR}/key.pem}"
    SSL_AUTO_GENERATE="${SSL_AUTO_GENERATE:-true}"

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

        log DEBUG "Certificate subject: $CERT_SUBJECT"
        log DEBUG "Certificate expires: $CERT_EXPIRES"

        # Update Apache configuration with the certificate paths in all SSL vhosts
        for vhost_file in /etc/apache2/sites-available/vhost-ssl*.conf; do
            if [[ -f "$vhost_file" ]]; then
                sed -i "s|SSLCertificateFile .*|SSLCertificateFile ${SSL_CERT_FILE}|g" "$vhost_file"
                sed -i "s|SSLCertificateKeyFile .*|SSLCertificateKeyFile ${SSL_KEY_FILE}|g" "$vhost_file"

                # Add chain certificate if provided
                if [[ -n "${SSL_CHAIN_FILE:-}" ]] && [[ -f "$SSL_CHAIN_FILE" ]]; then
                    if ! grep -q "SSLCertificateChainFile" "$vhost_file"; then
                        sed -i "/SSLCertificateKeyFile/a\    SSLCertificateChainFile ${SSL_CHAIN_FILE}" "$vhost_file"
                    else
                        sed -i "s|SSLCertificateChainFile .*|SSLCertificateChainFile ${SSL_CHAIN_FILE}|g" "$vhost_file"
                    fi
                fi
            fi
        done

    elif [[ "$SSL_AUTO_GENERATE" == "true" ]]; then
        # Set SSL_CONFIG path
        SSL_CONFIG="${SSL_DIR}/openssl.conf"

        # Generate self-signed certificates if they don't exist
        log INFO "Generating self-signed SSL certificates for HTTP/2..."

        # Generate private key (silent)
        if ! openssl genrsa -out "$SSL_KEY_FILE" 2048 >/dev/null 2>&1; then
            log WARNING "Failed to generate private key, SSL will be disabled"
            return 0
        fi

        # Generate self-signed certificate (silent)
        if ! openssl req -new -x509 -key "$SSL_KEY_FILE" -out "$SSL_CERT_FILE" -days 365 \
            -config "$SSL_CONFIG" -extensions v3_req \
            >/dev/null 2>&1; then

            log WARNING "Failed to generate certificate, SSL will be disabled"
            rm -f "$SSL_KEY_FILE" "$SSL_CONFIG" 2>/dev/null || true
            return 0
        fi

        # Set proper permissions
        chmod 644 "$SSL_CERT_FILE" 2>/dev/null || true
        chmod 600 "$SSL_KEY_FILE" 2>/dev/null || true
        chown www-data:www-data "$SSL_CERT_FILE" "$SSL_KEY_FILE" 2>/dev/null || true

        log SUCCESS "SSL certificates generated successfully"
        log DEBUG "Certificate: $SSL_CERT_FILE"
        log DEBUG "Private key: $SSL_KEY_FILE"
    else
        log WARNING "SSL certificates not found and auto-generation is disabled"
        log INFO "Please mount certificates or set SSL_AUTO_GENERATE=true"
        return 0
    fi

    # Create cache directories for SSL
    mkdir -p /var/cache/apache2
    chown www-data:www-data /var/cache/apache2
    chmod 755 /var/cache/apache2

    # Setup the appropriate Apache vhost configuration
    setup_apache_vhost

    log SUCCESS "SSL and Apache configuration completed"
}

# Execute main function
main_ssl_setup
