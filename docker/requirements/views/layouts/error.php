<?php
/**
 * Error layout template
 * 
 * @var Exception $error
 * @var string $message
 * @var string $timestamp
 */
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Requirements Check Error</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
        }
        .error-container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .error-header {
            background: linear-gradient(135deg, #e53935 0%, #c62828 100%);
            color: white;
            padding: 2rem;
            text-align: center;
        }
        .error-icon {
            font-size: 4rem;
            margin-bottom: 1rem;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.7; }
            100% { opacity: 1; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="row justify-content-center">
            <div class="col-lg-8 col-xl-6">
                <div class="error-container">
                    <div class="error-header">
                        <div class="error-icon">
                            <i class="bi bi-exclamation-triangle-fill"></i>
                        </div>
                        <h2 class="mb-0">Requirements Check Failed</h2>
                        <p class="mb-0 opacity-75">Something went wrong during the system check</p>
                    </div>
                    
                    <div class="p-4">
                        <div class="alert alert-danger" role="alert">
                            <h6 class="alert-heading">
                                <i class="bi bi-bug me-2"></i>
                                Error Details
                            </h6>
                            <p class="mb-0">
                                <code><?= ViewRenderer::escape($message) ?></code>
                            </p>
                        </div>
                        
                        <div class="d-grid gap-2 d-md-flex justify-content-md-center mb-4">
                            <button onclick="location.reload()" class="btn btn-primary">
                                <i class="bi bi-arrow-clockwise me-1"></i>
                                Try Again
                            </button>
                            <a href="?format=json" class="btn btn-outline-secondary">
                                <i class="bi bi-file-earmark-code me-1"></i>
                                View JSON
                            </a>
                        </div>
                        
                        <!-- Debug Information -->
                        <div class="card">
                            <div class="card-header">
                                <h6 class="mb-0">
                                    <i class="bi bi-info-circle me-2"></i>
                                    Debug Information
                                </h6>
                            </div>
                            <div class="card-body">
                                <dl class="row mb-0">
                                    <dt class="col-sm-4">PHP Version:</dt>
                                    <dd class="col-sm-8"><?= ViewRenderer::escape(PHP_VERSION) ?></dd>
                                    
                                    <dt class="col-sm-4">Server Software:</dt>
                                    <dd class="col-sm-8"><?= ViewRenderer::escape($_SERVER['SERVER_SOFTWARE'] ?? 'Unknown') ?></dd>
                                    
                                    <dt class="col-sm-4">Build Type:</dt>
                                    <dd class="col-sm-8"><?= ViewRenderer::escape(getenv('BUILD_TYPE') ?: 'Unknown') ?></dd>
                                    
                                    <dt class="col-sm-4">Error Time:</dt>
                                    <dd class="col-sm-8"><?= ViewRenderer::escape($timestamp) ?></dd>
                                    
                                    <?php if (isset($error) && $error instanceof Exception): ?>
                                    <dt class="col-sm-4">Error Type:</dt>
                                    <dd class="col-sm-8"><?= ViewRenderer::escape(get_class($error)) ?></dd>
                                    
                                    <dt class="col-sm-4">File:</dt>
                                    <dd class="col-sm-8"><?= ViewRenderer::escape($error->getFile()) ?>:<?= $error->getLine() ?></dd>
                                    <?php endif; ?>
                                </dl>
                            </div>
                        </div>
                        
                        <?php if (isset($error) && $error instanceof Exception): ?>
                        <div class="mt-3">
                            <details class="text-muted">
                                <summary class="btn btn-outline-secondary btn-sm">
                                    <i class="bi bi-code-square me-1"></i>
                                    View Stack Trace
                                </summary>
                                <pre class="mt-2 p-3 bg-light border rounded small"><code><?= ViewRenderer::escape($error->getTraceAsString()) ?></code></pre>
                            </details>
                        </div>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>