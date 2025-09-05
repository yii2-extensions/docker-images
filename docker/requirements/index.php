<?php

declare(strict_types=1);

// Set error reporting for development
error_reporting(E_ALL);
ini_set('display_errors', '1');

// Include the new classes
require_once __DIR__ . '/classes/ViewRenderer.php';
require_once __DIR__ . '/classes/ComponentHelper.php';
require_once __DIR__ . '/classes/RequirementsChecker.php';

// Determine output format
$outputFormat = 'html'; // default
$acceptHeader = $_SERVER['HTTP_ACCEPT'] ?? '';

// Check if JSON is requested
if (isset($_GET['format']) && $_GET['format'] === 'json') {
    $outputFormat = 'json';
} elseif (strpos($acceptHeader, 'application/json') !== false && strpos($acceptHeader, 'text/html') === false) {
    $outputFormat = 'json';
}

// Create checker instance
$checker = new RequirementsChecker();

try {
    // Perform the check
    $checker->check();
    
    if ($outputFormat === 'json') {
        // Return JSON response
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-cache, must-revalidate');
        header('Expires: 0');
        
        echo $checker->getJson();
    } else {
        // Return HTML response
        header('Content-Type: text/html; charset=utf-8');
        header('Cache-Control: no-cache, must-revalidate');
        header('Expires: 0');
        
        // Get the result data
        $result = $checker->getResult();
        $system = $result['system'];
        $summary = $result['summary'];
        $categories = $result['categories'];
        
        // Set global data for views
        ViewRenderer::setGlobalData([
            'result' => $result,
            'system' => $system,
            'summary' => $summary,
            'categories' => $categories
        ]);
        
        // Render the main layout
        echo ViewRenderer::renderLayout('main', [
            'result' => $result,
            'system' => $system,
            'summary' => $summary,
            'categories' => $categories
        ]);
    }
    
} catch (Exception $e) {
    // Handle errors gracefully
    if ($outputFormat === 'json') {
        header('Content-Type: application/json; charset=utf-8');
        http_response_code(500);
        
        echo json_encode([
            'error' => true,
            'message' => 'Requirements check failed: ' . $e->getMessage(),
            'timestamp' => date('c'),
            'trace' => $e->getTraceAsString()
        ], JSON_PRETTY_PRINT);
    } else {
        header('Content-Type: text/html; charset=utf-8');
        http_response_code(500);
        
        echo ViewRenderer::renderLayout('error', [
            'error' => $e,
            'message' => $e->getMessage(),
            'timestamp' => date('c')
        ]);
    }
}