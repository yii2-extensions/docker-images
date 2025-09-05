<?php
/**
 * Category Section Component - Clean separated version
 * @var array $category
 * @var int $index
 */

$categoryIcon = ComponentHelper::getCategoryIcon($category['name']);
$summary = $category['summary'];
$successRate = $summary['total'] > 0 ? round(($summary['passed'] / $summary['total']) * 100, 1) : 0;
?>

<div class="card border-0 shadow-sm">
    <div class="card-header bg-transparent border-bottom-0 py-3">
        <div class="row align-items-center">
            <div class="col">
                <h5 class="mb-0">
                    <i class="bi bi-<?= $categoryIcon ?> text-primary me-2"></i>
                    <?= ViewRenderer::escape($category['name']) ?>
                </h5>
                <small class="text-muted">
                    <?= ViewRenderer::formatNumber($summary['total']) ?> requirements, 
                    <?= ViewRenderer::formatNumber($summary['passed']) ?> passed
                </small>
            </div>
            <div class="col-auto">
                <div class="d-flex align-items-center gap-2">
                    <div class="progress" style="width: 100px; height: 8px;">
                        <div class="progress-bar bg-success" style="width: <?= $successRate ?>%"></div>
                    </div>
                    <span class="badge bg-<?= ComponentHelper::getOverallStatus($summary) ?> fs-6">
                        <?= ViewRenderer::formatPercent($successRate) ?>
                    </span>
                </div>
            </div>
        </div>
    </div>
    
    <div class="card-body">
        <?php if (empty($category['requirements'])): ?>
            <div class="text-center text-muted py-4">
                <i class="bi bi-info-circle fs-1 mb-3"></i>
                <p>No requirements defined for this category.</p>
            </div>
        <?php else: ?>
            <div class="requirements-list">
                <?php foreach ($category['requirements'] as $requirement): ?>
                    <?php 
                    $statusClass = ComponentHelper::getStatusClass($requirement['status']);
                    $statusIcon = ComponentHelper::getStatusIcon($requirement['status']);
                    ?>
                    <div class="requirement-item status-<?= $requirement['status'] ?> p-3 mb-3 bg-light rounded">
                        <div class="row align-items-start">
                            <div class="col-auto">
                                <div class="status-indicator">
                                    <i class="bi bi-<?= $statusIcon ?> text-<?= $statusClass ?> fs-4"></i>
                                </div>
                            </div>
                            
                            <div class="col">
                                <div class="requirement-header">
                                    <h6 class="mb-1 fw-semibold">
                                        <?= ViewRenderer::escape($requirement['name']) ?>
                                        <?php if ($requirement['mandatory']): ?>
                                            <span class="badge bg-danger ms-2">Required</span>
                                        <?php else: ?>
                                            <span class="badge bg-secondary ms-2">Optional</span>
                                        <?php endif; ?>
                                    </h6>
                                    
                                    <?php if (!empty($requirement['version_info'])): ?>
                                        <div class="version-info mb-2">
                                            <small class="text-muted">
                                                <i class="bi bi-tag me-1"></i>
                                                Version: <code><?= ViewRenderer::escape($requirement['version_info']) ?></code>
                                            </small>
                                        </div>
                                    <?php endif; ?>
                                </div>
                                
                                <div class="requirement-content">
                                    <?php if (!empty($requirement['description'])): ?>
                                        <p class="text-muted mb-2">
                                            <?= ViewRenderer::escape($requirement['description']) ?>
                                        </p>
                                    <?php endif; ?>
                                    
                                    <?php if (!empty($requirement['recommendation']) && !$requirement['condition']): ?>
                                        <div class="alert alert-<?= $requirement['mandatory'] ? 'danger' : 'warning' ?> alert-sm py-2 mb-2">
                                            <i class="bi bi-lightbulb me-1"></i>
                                            <small><strong>Recommendation:</strong> <?= ViewRenderer::escape($requirement['recommendation']) ?></small>
                                        </div>
                                    <?php endif; ?>
                                    
                                    <?php if (isset($requirement['metrics']) && !empty($requirement['metrics'])): ?>
                                        <div class="performance-metrics mt-2">
                                            <small class="text-muted fw-semibold">Performance Metrics:</small>
                                            <div class="metrics-grid mt-1">
                                                <?php foreach ($requirement['metrics'] as $key => $value): ?>
                                                    <div class="metric-item">
                                                        <span class="metric-label"><?= ViewRenderer::escape(ucfirst(str_replace('_', ' ', $key))) ?>:</span>
                                                        <span class="metric-value"><?= ViewRenderer::escape($value) ?></span>
                                                    </div>
                                                <?php endforeach; ?>
                                            </div>
                                        </div>
                                    <?php endif; ?>
                                </div>
                            </div>
                            
                            <div class="col-auto">
                                <div class="requirement-status text-end">
                                    <div class="status-badge badge bg-<?= $statusClass ?> mb-1">
                                        <?= ucfirst($requirement['status']) ?>
                                    </div>
                                    <?php if ($requirement['condition']): ?>
                                        <div class="text-success">
                                            <small><i class="bi bi-check-lg me-1"></i>Passed</small>
                                        </div>
                                    <?php else: ?>
                                        <div class="text-<?= $requirement['mandatory'] ? 'danger' : 'warning' ?>">
                                            <small><i class="bi bi-x-lg me-1"></i><?= $requirement['mandatory'] ? 'Failed' : 'Warning' ?></small>
                                        </div>
                                    <?php endif; ?>
                                </div>
                            </div>
                        </div>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>
</div>

<style>
.requirement-item {
    transition: all 0.3s ease;
    border-left: 4px solid #e9ecef;
}

.requirement-item.status-passed {
    border-left-color: var(--bs-success);
    background-color: rgba(var(--bs-success-rgb), 0.05) !important;
}

.requirement-item.status-warning {
    border-left-color: var(--bs-warning);
    background-color: rgba(var(--bs-warning-rgb), 0.05) !important;
}

.requirement-item.status-failed {
    border-left-color: var(--bs-danger);
    background-color: rgba(var(--bs-danger-rgb), 0.05) !important;
}

.requirement-item:hover {
    transform: translateX(5px);
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 0.5rem;
}

.metric-item {
    display: flex;
    justify-content: space-between;
    padding: 0.25rem 0.5rem;
    background: rgba(0,0,0,0.05);
    border-radius: 4px;
}

.metric-label {
    font-weight: 500;
    color: #6c757d;
}

.metric-value {
    font-family: monospace;
    font-size: 0.9em;
}

.summary-stat .stat-number {
    font-size: 1.25rem;
    font-weight: 700;
    line-height: 1;
}

.summary-stat .stat-label {
    font-size: 0.75rem;
    color: #6c757d;
    margin-top: 0.25rem;
}

.alert-sm {
    padding: 0.5rem 0.75rem;
    font-size: 0.875rem;
}

.status-indicator {
    width: 40px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    background: rgba(0,0,0,0.05);
}
</style>