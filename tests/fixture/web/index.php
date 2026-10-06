<?php

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

echo json_encode(
    [
        'fixture' => 'ok',
        'method' => $_SERVER['REQUEST_METHOD'] ?? '',
        'uri' => $_SERVER['REQUEST_URI'] ?? '',
        'https' => ($_SERVER['HTTPS'] ?? '') === 'on',
        'protocol' => $_SERVER['SERVER_PROTOCOL'] ?? '',
        'functions' => [
            'exec' => function_exists('exec'),
            'shell_exec' => function_exists('shell_exec'),
            'parse_ini_file' => function_exists('parse_ini_file'),
        ],
    ],
);
