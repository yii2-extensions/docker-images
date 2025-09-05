<?php
/**
 * Summary Cards Component - Clean separated version
 * @var array $summary
 */

$successRate = $summary['total'] > 0 ? round(($summary['passed'] / $summary['total']) * 100, 1) : 0;
?>

<div class="row g-4">
    <!-- Total Checks Card -->
    <div class="col-lg-3 col-md-6">
        <div class="card metric-card h-100 border-0 shadow-sm">
            <div class="card-body text-center">
                <div class="metric-icon text-primary mb-3">
                    <i class="bi bi-list-check"></i>
                </div>
                <h5 class="card-title text-muted">Total Checks</h5>
                <div class="metric-value text-primary mb-2"><?= ViewRenderer::formatNumber($summary['total']) ?></div>
                <div class="metric-subtitle">
                    <small class="text-muted">System requirements evaluated</small>
                </div>
            </div>
        </div>
    </div>

    <!-- Passed Card -->
    <div class="col-lg-3 col-md-6">
        <div class="card metric-card h-100 border-0 shadow-sm border-start border-success border-3">
            <div class="card-body text-center">
                <div class="metric-icon text-success mb-3">
                    <i class="bi bi-check-circle-fill"></i>
                </div>
                <h5 class="card-title text-muted">Passed</h5>
                <div class="metric-value text-success mb-2"><?= ViewRenderer::formatNumber($summary['passed']) ?></div>
                <div class="metric-subtitle">
                    <small class="text-success"><?= ViewRenderer::formatPercent($successRate) ?> success rate</small>
                </div>
            </div>
        </div>
    </div>

    <!-- Warnings Card -->
    <div class="col-lg-3 col-md-6">
        <div class="card metric-card h-100 border-0 shadow-sm border-start border-warning border-3">
            <div class="card-body text-center">
                <div class="metric-icon text-warning mb-3">
                    <i class="bi bi-exclamation-triangle-fill"></i>
                </div>
                <h5 class="card-title text-muted">Warnings</h5>
                <div class="metric-value text-warning mb-2"><?= ViewRenderer::formatNumber($summary['warnings']) ?></div>
                <div class="metric-subtitle">
                    <small class="text-warning">
                        <?php if ($summary['warnings'] > 0): ?>
                            Optional improvements available
                        <?php else: ?>
                            No warnings detected
                        <?php endif; ?>
                    </small>
                </div>
            </div>
        </div>
    </div>

    <!-- Failed Card -->
    <div class="col-lg-3 col-md-6">
        <div class="card metric-card h-100 border-0 shadow-sm border-start border-danger border-3">
            <div class="card-body text-center">
                <div class="metric-icon text-danger mb-3">
                    <i class="bi bi-x-circle-fill"></i>
                </div>
                <h5 class="card-title text-muted">Failed</h5>
                <div class="metric-value text-danger mb-2"><?= ViewRenderer::formatNumber($summary['failed']) ?></div>
                <div class="metric-subtitle">
                    <small class="text-danger">
                        <?php if ($summary['failed'] > 0): ?>
                            Critical issues found
                        <?php else: ?>
                            All requirements met
                        <?php endif; ?>
                    </small>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Progress Overview -->
<div class="row mt-4">
    <div class="col-12">
        <div class="card border-0 shadow-sm">
            <div class="card-body">
                <div class="row align-items-center">
                    <div class="col-md-8">
                        <h6 class="mb-2">Overall Progress</h6>
                        <div class="progress mb-2" style="height: 8px;">
                            <div class="progress-bar bg-success" style="width: <?= $successRate ?>%"></div>
                            <div class="progress-bar bg-warning" style="width: <?= $summary['total'] > 0 ? round(($summary['warnings'] / $summary['total']) * 100, 1) : 0 ?>%"></div>
                            <div class="progress-bar bg-danger" style="width: <?= $summary['total'] > 0 ? round(($summary['failed'] / $summary['total']) * 100, 1) : 0 ?>%"></div>
                        </div>
                        <small class="text-muted">
                            <?= ViewRenderer::formatNumber($summary['passed']) ?> passed, 
                            <?= ViewRenderer::formatNumber($summary['warnings']) ?> warnings, 
                            <?= ViewRenderer::formatNumber($summary['failed']) ?> failed
                        </small>
                    </div>
                    <div class="col-md-4 text-md-end">
                        <div class="btn-group btn-group-sm" role="group">
                            <button type="button" class="btn btn-outline-primary" onclick="exportReport()">
                                <i class="bi bi-download"></i> Export
                            </button>
                            <button type="button" class="btn btn-outline-secondary" onclick="window.location.reload()">
                                <i class="bi bi-arrow-clockwise"></i> Refresh
                            </button>
                            <a href="?format=json" class="btn btn-outline-info" target="_blank">
                                <i class="bi bi-file-earmark-code"></i> JSON
                            </a>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>