<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

$health = [
    'status' => 'healthy',
    'timestamp' => date('c'),
    'service' => getenv('SERVICE_NAME') ?: 'yii2-app',
    'version' => getenv('APP_VERSION') ?: 'unknown',
    'environment' => getenv('YII_ENV') ?: 'unknown',
    'php_version' => PHP_VERSION,
    'checks' => [],
];

foreach (['pdo', 'intl', 'opcache'] as $extension) {
    $health['checks']['ext_' . $extension] = extension_loaded($extension) ? 'ok' : 'missing';
}

echo json_encode($health, JSON_PRETTY_PRINT);
