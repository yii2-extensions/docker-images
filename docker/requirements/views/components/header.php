<?php

declare(strict_types=1);

/**
 * Sticky Header Component
 * 
 * @var array $system
 * @var array $summary
 */
$overallStatus = $summary['errors'] > 0 ? 'danger' : ($summary['warnings'] > 0 ? 'warning' : 'success');
$statusText = $summary['errors'] > 0 ? 'Failed' : ($summary['warnings'] > 0 ? 'Warning' : 'Passed');
$statusIcon = $summary['errors'] > 0 ? 'exclamation-triangle' : ($summary['warnings'] > 0 ? 'exclamation-circle' : 'check-circle');
?>
<header class="sticky-header" id="stickyHeader">
    <div class="container-fluid">
        <div class="row align-items-center">
            <!-- Brand Section -->
            <div class="col-md-6 col-lg-4">
                <div class="header-brand">
                    <div class="yii-logo">Yii</div>
                    <div class="brand-info">
                        <h1 class="brand-title">Requirements Checker</h1>
                        <p class="brand-subtitle">System validation for Yii2 applications</p>
                    </div>
                </div>
            </div>
            
            <!-- Status Section -->
            <div class="col-md-6 col-lg-4 text-center">
                <div class="header-status">
                    <div class="status-indicator status-<?php echo $overallStatus; ?>">
                        <i class="bi bi-<?php echo $statusIcon; ?>"></i>
                    </div>
                    <div class="status-text">
                        <span class="status-label"><?php echo $statusText; ?></span>
                        <small class="text-muted"><?php echo $summary['total']; ?> checks</small>
                    </div>
                </div>
            </div>
            
            <!-- Info Section -->
            <div class="col-lg-4 text-end d-none d-lg-block">
                <div class="header-info">
                    <div class="info-badges">
                        <span class="badge version-badge">PHP <?php echo $system['php_version']; ?></span>
                        <span class="badge build-badge bg-info"><?php echo strtoupper($system['build_type']); ?></span>
                        <span class="badge env-badge bg-secondary"><?php echo strtoupper($system['environment']); ?></span>
                    </div>
                    <div class="header-actions">
                        <button class="btn btn-outline-light btn-sm" onclick="window.print()">
                            <i class="bi bi-printer"></i>
                        </button>
                        <button class="btn btn-outline-light btn-sm" onclick="exportReport()">
                            <i class="bi bi-download"></i>
                        </button>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Progress Bar -->
        <div class="header-progress">
            <?php 
            $successRate = $summary['total'] > 0 ? ($summary['passed'] / $summary['total']) * 100 : 0;
            $warningRate = $summary['total'] > 0 ? ($summary['warnings'] / $summary['total']) * 100 : 0;
            $errorRate = $summary['total'] > 0 ? ($summary['failed'] / $summary['total']) * 100 : 0;
            ?>
            <div class="progress">
                <div class="progress-bar bg-success" style="width: <?php echo $successRate; ?>%"></div>
                <div class="progress-bar bg-warning" style="width: <?php echo $warningRate; ?>%"></div>
                <div class="progress-bar bg-danger" style="width: <?php echo $errorRate; ?>%"></div>
            </div>
        </div>
    </div>
</header>