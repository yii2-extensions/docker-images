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
    ],
);
