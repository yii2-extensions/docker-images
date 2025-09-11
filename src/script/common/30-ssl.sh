#!/bin/bash
#==============================================================================
# SSL setup for Apache with HTTP/2 support
#==============================================================================

# Main SSL setup logic
main_ssl_setup() {
    # Early exit if SSL is disabled
    if [[ "${APACHE_SSL_ENABLED:-true}" != "true" ]]; then
        log INFO "SSL is disabled via APACHE_SSL_ENABLED=false"
        setup_apache_vhost
        return 0
    fi

    # Set up environment variables with defaults
    local ssl_dir="${SSL_DIR:-/etc/apache2/ssl}"
    local ssl_cert_file="${SSL_CERT_FILE:-${ssl_dir}/cert.pem}"
    local ssl_key_file="${SSL_KEY_FILE:-${ssl_dir}/key.pem}"
    local ssl_auto_generate="${SSL_AUTO_GENERATE:-true}"
    local ssl_config="${ssl_dir}/openssl.conf"

    # Set up SSL directory
    setup_ssl_directory "$ssl_dir"

    # Handle SSL certificates (external or auto-generated)
    if ! handle_ssl_certificates "$ssl_dir" "$ssl_cert_file" "$ssl_key_file" "$ssl_auto_generate" "$ssl_config"; then
        log WARNING "SSL setup failed, falling back to HTTP-only"
        export APACHE_SSL_ENABLED="false"
        setup_apache_vhost
        return 0
    fi

    # Set up SSL cache and complete configuration
    setup_ssl_cache
    setup_apache_vhost

    log SUCCESS "SSL configuration completed successfully"
}

generate_self_signed_certificate() {
    local ssl_cert_file="$1"
    local ssl_key_file="$2"
    local ssl_config="$3"

    log INFO "Generating self-signed SSL certificates for HTTP/2..."

    # Generate private key and certificate in one atomic operation
    if ! openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$ssl_key_file" -out "$ssl_cert_file" \
        -days 365 -config "$ssl_config" -extensions v3_req \
        -sha256 >/dev/null 2>&1; then

        log ERROR "Failed to generate SSL certificates"
        rm -f "$ssl_key_file" "$ssl_cert_file" 2>/dev/null
        return 1
    fi

    # Set proper permissions
    chmod 644 "$ssl_cert_file" 2>/dev/null
    chmod 600 "$ssl_key_file" 2>/dev/null
    chown www-data:www-data "$ssl_cert_file" "$ssl_key_file" 2>/dev/null

    log SUCCESS "Self-signed SSL certificates generated"

    # Only show paths in debug mode
    if [[ "${DEBUG_ENTRYPOINT:-false}" == "true" ]]; then
        log DEBUG "Certificate: $ssl_cert_file"
        log DEBUG "Private key: $ssl_key_file"
    fi

    return 0
}

handle_ssl_certificates() {
    local ssl_dir="$1"
    local ssl_cert_file="$2"
    local ssl_key_file="$3"
    local ssl_auto_generate="$4"
    local ssl_config="$5"

    # Check if external certificates are provided
    if [[ -f "$ssl_cert_file" && -f "$ssl_key_file" ]]; then
        log INFO "Using existing SSL certificates"

        # Log certificate details only in debug mode
        if [[ "${DEBUG_ENTRYPOINT:-false}" == "true" ]]; then
            local cert_subject cert_expires
            cert_subject=$(openssl x509 -in "$ssl_cert_file" -subject -noout 2>/dev/null | sed 's/subject= *//' || echo "Unknown")
            cert_expires=$(openssl x509 -in "$ssl_cert_file" -enddate -noout 2>/dev/null | sed 's/notAfter=//' || echo "Unknown")
            log DEBUG "Certificate subject: $cert_subject"
            log DEBUG "Certificate expires: $cert_expires"
        fi

        # Update vhost configurations
        update_vhost_certificates "$ssl_cert_file" "$ssl_key_file" "${SSL_CHAIN_FILE:-}"
        return 0

    elif [[ "$ssl_auto_generate" == "true" ]]; then
        log INFO "Auto-generating self-signed SSL certificates"

        # Generate self-signed certificate
        if ! generate_self_signed_certificate "$ssl_cert_file" "$ssl_key_file" "$ssl_config"; then
            log WARNING "SSL certificate generation failed"
            return 1
        fi

        # Update vhost configurations
        update_vhost_certificates "$ssl_cert_file" "$ssl_key_file"
        return 0

    else
        log WARNING "SSL certificates not found and auto-generation is disabled"
        log INFO "Please mount certificates or set SSL_AUTO_GENERATE=true"
        return 1
    fi
}

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
    if [[ "${SSL_AUTO_GENERATE:-true}" == "true" || "${APACHE_DISABLE_OCSP_STAPLING:-false}" == "true" ]]; then
        log INFO "Disabling OCSP stapling for self-signed certificates"

        # Comment out OCSP stapling lines in apache2.conf
        sed -i 's/^\s*SSLStaplingCache/    # SSLStaplingCache/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingErrorCacheTimeout/    # SSLStaplingErrorCacheTimeout/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingFakeTryLater/    # SSLStaplingFakeTryLater/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingResponderTimeout/    # SSLStaplingResponderTimeout/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingReturnResponderErrors/    # SSLStaplingReturnResponderErrors/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*SSLStaplingStandardCacheTimeout/    # SSLStaplingStandardCacheTimeout/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*SSLUseStapling on/    # SSLUseStapling on/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
    else
        log INFO "OCSP stapling enabled (external certificates)"

        # Uncomment OCSP stapling lines if they were previously commented
        sed -i 's/^\s*#\s*SSLStaplingCache/    SSLStaplingCache/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingErrorCacheTimeout/    SSLStaplingErrorCacheTimeout/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingFakeTryLater/    SSLStaplingFakeTryLater/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingResponderTimeout/    SSLStaplingResponderTimeout/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingReturnResponderErrors/    SSLStaplingReturnResponderErrors/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLStaplingStandardCacheTimeout/    SSLStaplingStandardCacheTimeout/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
        sed -i 's/^\s*#\s*SSLUseStapling on/    SSLUseStapling on/' /etc/apache2/conf-available/03-ssl-tls.conf 2>/dev/null || true
    fi

    # List active sites only in debug mode
    if [[ "${DEBUG_ENTRYPOINT:-false}" == "true" ]]; then
        if ls /etc/apache2/sites-enabled/*.conf >/dev/null 2>&1; then
            for conf in /etc/apache2/sites-enabled/*.conf; do
                if [[ -L "$conf" && -e "$conf" ]]; then
                    log DEBUG "Active site: $(basename "$conf")"
                fi
            done
        fi
    fi
}

setup_ssl_cache() {
    if [[ "${DEBUG_ENTRYPOINT:-false}" == "true" ]]; then
        log DEBUG "Setting up SSL cache directory"
    fi

    mkdir -p /var/cache/apache2
    chown www-data:www-data /var/cache/apache2
    chmod 755 /var/cache/apache2
}

setup_ssl_directory() {
    local ssl_dir="$1"

    if [[ ! -d "$ssl_dir" ]]; then
        log INFO "Creating SSL directory: $ssl_dir"
        mkdir -p "$ssl_dir"
        chown www-data:www-data "$ssl_dir"
        chmod 755 "$ssl_dir"
    fi
}

update_vhost_certificates() {
    local ssl_cert_file="$1"
    local ssl_key_file="$2"
    local ssl_chain_file="${3:-}"

    # Update all SSL-enabled vhost files
    for vhost_file in /etc/apache2/sites-available/vhost-ssl*.conf; do
        if [[ -f "$vhost_file" ]]; then
            if [[ "${DEBUG_ENTRYPOINT:-false}" == "true" ]]; then
                log DEBUG "Updating certificate paths in $(basename "$vhost_file")"
            fi

            sed -i "s|SSLCertificateFile .*|SSLCertificateFile ${ssl_cert_file}|g" "$vhost_file"
            sed -i "s|SSLCertificateKeyFile .*|SSLCertificateKeyFile ${ssl_key_file}|g" "$vhost_file"

            # Handle chain certificate if provided
            if [[ -n "$ssl_chain_file" && -f "$ssl_chain_file" ]]; then
                if ! grep -q "SSLCertificateChainFile" "$vhost_file"; then
                    sed -i "/SSLCertificateKeyFile/a\    SSLCertificateChainFile ${ssl_chain_file}" "$vhost_file"
                else
                    sed -i "s|SSLCertificateChainFile .*|SSLCertificateChainFile ${ssl_chain_file}|g" "$vhost_file"
                fi
            fi
        fi
    done
}

# Execute main function
main_ssl_setup
