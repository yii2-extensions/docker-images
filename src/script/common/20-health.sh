#!/bin/bash
#==============================================================================
# Health create endpoint
#==============================================================================

health_create_endpoint() {
    [[ "${ENABLE_HEALTH_ENDPOINT:-true}" != "true" ]] && return

    local health_path="${HEALTHCHECK_PATH:-/health}"
    local health_file="/var/www/app/web${health_path}"
    [[ "${health_path}" != *".php" ]] && health_file="${health_file}/index.php"

    # Check if health endpoint already exists
    if [[ -f "$health_file" ]]; then
        log INFO "Health endpoint already exists at ${health_path}"
        return 0
    fi

    log INFO "Creating health endpoint at ${health_path}"

    # Check if we can write to the target location
    if ! mkdir -p "$(dirname "$health_file")" 2>/dev/null; then
        log WARNING "Cannot create health endpoint directory - filesystem may be read-only"
        return 0
    fi

    # Write the health endpoint file
    cat > "$health_file" << 'HEALTH_PHP'
<?php
header('Content-Type: application/json; charset=utf-8');

$health = [
    'status' => 'healthy',
    'timestamp' => date('c'),
    'service' => getenv('SERVICE_NAME') ?: 'yii2-app',
    'version' => getenv('APP_VERSION') ?: 'unknown',
    'environment' => getenv('YII_ENV') ?: 'unknown',
    'php_version' => PHP_VERSION,
    'checks' => []
];

// Basic extension checks
$extensions = ['pdo', 'intl', 'opcache'];
foreach ($extensions as $ext) {
    $health['checks']["ext_${ext}"] = extension_loaded($ext) ? 'ok' : 'missing';
}

echo json_encode($health, JSON_PRETTY_PRINT);
HEALTH_PHP

    # Check if the write was successful
    if [[ ! -f "$health_file" ]]; then
        log ERROR "Failed to write health endpoint at ${health_path}"
        return 1
    fi

    # Set permissions only if file exists
    chown www-data:www-data "$health_file" 2>/dev/null || true
    chmod 644 "$health_file" 2>/dev/null || true

    log SUCCESS "Health endpoint created"
}
