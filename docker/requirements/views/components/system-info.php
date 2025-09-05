<?php
/**
 * System Information Component - Clean separated version
 * @var array $system
 */

$memoryUsage = memory_get_usage(true);
$peakMemory = memory_get_peak_usage(true);
$currentMemoryMB = round($memoryUsage / 1024 / 1024, 2);
$peakMemoryMB = round($peakMemory / 1024 / 1024, 2);
?>

<div class="card border-0 shadow-sm">
    <div class="card-header bg-transparent border-bottom-0 py-3">
        <div class="row align-items-center">
            <div class="col">
                <h5 class="mb-0">
                    <i class="bi bi-info-circle text-primary me-2"></i>
                    System Information
                </h5>
                <small class="text-muted">Current environment details</small>
            </div>
            <div class="col-auto">
                <?= ComponentHelper::badge($system['build_type'], 'primary') ?>
                <?= ComponentHelper::badge('PHP ' . $system['php_version'], 'secondary') ?>
            </div>
        </div>
    </div>
    
    <div class="card-body">
        <div class="row g-4">
            <!-- Core System -->
            <div class="col-md-6">
                <h6 class="text-muted mb-3">
                    <i class="bi bi-cpu"></i> Core System
                </h6>
                <dl class="row">
                    <dt class="col-sm-5">PHP Version:</dt>
                    <dd class="col-sm-7">
                        <span class="badge bg-<?= version_compare($system['php_version'], '8.1.0', '>=') ? 'success' : 'warning' ?>">
                            <?= ViewRenderer::escape($system['php_version']) ?>
                        </span>
                    </dd>
                    
                    <dt class="col-sm-5">Server API:</dt>
                    <dd class="col-sm-7">
                        <code><?= ViewRenderer::escape($system['php_sapi']) ?></code>
                    </dd>
                    
                    <dt class="col-sm-5">Operating System:</dt>
                    <dd class="col-sm-7"><?= ViewRenderer::escape($system['os']) ?></dd>
                    
                    <dt class="col-sm-5">Architecture:</dt>
                    <dd class="col-sm-7">
                        <span class="badge bg-secondary"><?= ViewRenderer::escape($system['architecture']) ?></span>
                    </dd>
                </dl>
            </div>
            
            <!-- Performance -->
            <div class="col-md-6">
                <h6 class="text-muted mb-3">
                    <i class="bi bi-speedometer2"></i> Performance
                </h6>
                <dl class="row">
                    <dt class="col-sm-5">Memory Limit:</dt>
                    <dd class="col-sm-7">
                        <span class="badge bg-info"><?= ViewRenderer::escape($system['memory_limit']) ?></span>
                    </dd>
                    
                    <dt class="col-sm-5">Current Usage:</dt>
                    <dd class="col-sm-7"><?= $currentMemoryMB ?> MB</dd>
                    
                    <dt class="col-sm-5">Peak Usage:</dt>
                    <dd class="col-sm-7"><?= $peakMemoryMB ?> MB</dd>
                    
                    <dt class="col-sm-5">Max Execution:</dt>
                    <dd class="col-sm-7">
                        <?= ViewRenderer::escape($system['max_execution_time']) ?> seconds
                    </dd>
                </dl>
            </div>
            
            <!-- Environment -->
            <div class="col-md-6">
                <h6 class="text-muted mb-3">
                    <i class="bi bi-gear"></i> Environment
                </h6>
                <dl class="row">
                    <dt class="col-sm-5">Environment:</dt>
                    <dd class="col-sm-7">
                        <span class="badge bg-<?= $system['environment'] === 'prod' ? 'success' : 'warning' ?>">
                            <?= ViewRenderer::escape(strtoupper($system['environment'])) ?>
                        </span>
                    </dd>
                    
                    <dt class="col-sm-5">Build Type:</dt>
                    <dd class="col-sm-7">
                        <span class="badge bg-primary"><?= ViewRenderer::escape(strtoupper($system['build_type'])) ?></span>
                    </dd>
                    
                    <dt class="col-sm-5">Server Software:</dt>
                    <dd class="col-sm-7">
                        <small><?= ViewRenderer::escape($system['server_software']) ?></small>
                    </dd>
                    
                    <dt class="col-sm-5">System Uptime:</dt>
                    <dd class="col-sm-7"><?= ViewRenderer::escape($system['uptime']) ?></dd>
                </dl>
            </div>
            
            <!-- Timestamp -->
            <div class="col-md-6">
                <h6 class="text-muted mb-3">
                    <i class="bi bi-clock"></i> Timing
                </h6>
                <dl class="row">
                    <dt class="col-sm-5">Check Time:</dt>
                    <dd class="col-sm-7">
                        <small><?= ViewRenderer::escape($system['timestamp']) ?></small>
                    </dd>
                    
                    <dt class="col-sm-5">Timezone:</dt>
                    <dd class="col-sm-7">
                        <small><?= ViewRenderer::escape(date_default_timezone_get()) ?></small>
                    </dd>
                    
                    <dt class="col-sm-5">Loaded Extensions:</dt>
                    <dd class="col-sm-7">
                        <span class="badge bg-info"><?= count(get_loaded_extensions()) ?> extensions</span>
                    </dd>
                </dl>
            </div>
        </div>
        
        <!-- Memory Usage Progress -->
        <div class="row mt-4">
            <div class="col-12">
                <h6 class="text-muted mb-2">Memory Usage</h6>
                <?php
                $memoryLimitBytes = 0;
                $memoryLimit = $system['memory_limit'];
                if ($memoryLimit !== '-1') {
                    $checker = new RequirementsChecker();
                    $memoryLimitBytes = $checker->getByteSize($memoryLimit);
                    $usagePercentage = $memoryLimitBytes > 0 ? ($memoryUsage / $memoryLimitBytes) * 100 : 0;
                } else {
                    $usagePercentage = 0;
                    $memoryLimitBytes = 'Unlimited';
                }
                ?>
                <div class="progress mb-2" style="height: 6px;">
                    <div class="progress-bar bg-<?= $usagePercentage > 80 ? 'danger' : ($usagePercentage > 60 ? 'warning' : 'success') ?>" 
                         style="width: <?= min(100, max(1, $usagePercentage)) ?>%"></div>
                </div>
                <div class="d-flex justify-content-between">
                    <small class="text-muted">
                        Current: <?= $currentMemoryMB ?> MB | Peak: <?= $peakMemoryMB ?> MB
                    </small>
                    <small class="text-muted">
                        Limit: <?= $memoryLimitBytes === 'Unlimited' ? $memoryLimitBytes : ComponentHelper::formatBytes($memoryLimitBytes) ?>
                    </small>
                </div>
            </div>
        </div>
    </div>
</div>