<?php
/**
 * Status Alert Partial
 * @var array $summary
 */
$overallStatus = $summary['errors'] > 0 ? 'danger' : ($summary['warnings'] > 0 ? 'warning' : 'success');
$statusIcon = $summary['errors'] > 0 ? 'exclamation-triangle-fill' : ($summary['warnings'] > 0 ? 'exclamation-circle-fill' : 'check-circle-fill');
?>

<div class="alert alert-<?php echo $overallStatus; ?> alert-dismissible border-0 shadow-sm mb-4" role="alert">
    <div class="d-flex align-items-start">
        <div class="alert-icon me-3">
            <i class="bi bi-<?php echo $statusIcon; ?> fs-2"></i>
        </div>
        <div class="flex-grow-1">
            <?php if ($summary['errors'] > 0): ?>
                <h4 class="alert-heading mb-2">
                    <i class="bi bi-shield-x me-2"></i>
                    System Requirements Not Met
                </h4>
                <p class="mb-3">
                    Your server configuration has <strong><?php echo $summary['errors']; ?> critical issue<?php echo $summary['errors'] > 1 ? 's' : ''; ?></strong> 
                    that must be resolved before running this Yii2 application safely.
                </p>
                <div class="alert-actions">
                    <div class="row">
                        <div class="col-md-8">
                            <p class="mb-2"><strong>Next Steps:</strong></p>
                            <ul class="mb-0">
                                <li>Review the failed requirements below</li>
                                <li>Install missing PHP extensions</li>
                                <li>Update configuration settings</li>
                                <li>Restart your web server after changes</li>
                            </ul>
                        </div>
                        <div class="col-md-4 text-md-end">
                            <button class="btn btn-light btn-sm" onclick="scrollToFirstError()">
                                <i class="bi bi-arrow-down"></i>
                                Show First Error
                            </button>
                        </div>
                    </div>
                </div>

            <?php elseif ($summary['warnings'] > 0): ?>
                <h4 class="alert-heading mb-2">
                    <i class="bi bi-shield-check me-2"></i>
                    System Ready with Warnings
                </h4>
                <p class="mb-3">
                    Your server meets the minimum requirements but has <strong><?php echo $summary['warnings']; ?> warning<?php echo $summary['warnings'] > 1 ? 's' : ''; ?></strong> 
                    that should be addressed for optimal performance.
                </p>
                <div class="alert-actions">
                    <div class="row">
                        <div class="col-md-8">
                            <p class="mb-2"><strong>Recommendations:</strong></p>
                            <ul class="mb-0">
                                <li>Install optional extensions for better performance</li>
                                <li>Enable caching mechanisms (OPcache, APCu)</li>
                                <li>Optimize PHP configuration settings</li>
                                <li>Consider upgrading to newer versions</li>
                            </ul>
                        </div>
                        <div class="col-md-4 text-md-end">
                            <button class="btn btn-light btn-sm" onclick="scrollToFirstWarning()">
                                <i class="bi bi-arrow-down"></i>
                                Show Warnings
                            </button>
                        </div>
                    </div>
                </div>

            <?php else: ?>
                <h4 class="alert-heading mb-2">
                    <i class="bi bi-shield-fill-check me-2"></i>
                    Excellent! All Requirements Met
                </h4>
                <p class="mb-3">
                    Your server configuration fully satisfies all requirements for running this Yii2 application. 
                    You're ready to deploy and run your application with confidence!
                </p>
                <div class="alert-actions">
                    <div class="row">
                        <div class="col-md-8">
                            <p class="mb-2"><strong>You can now:</strong></p>
                            <ul class="mb-0">
                                <li>Deploy your Yii2 application</li>
                                <li>Configure your database connections</li>
                                <li>Set up your application environment</li>
                                <li>Monitor performance metrics</li>
                            </ul>
                        </div>
                        <div class="col-md-4 text-md-end">
                            <div class="btn-group-vertical w-100">
                                <button class="btn btn-light btn-sm" onclick="exportReport()">
                                    <i class="bi bi-download"></i>
                                    Download Report
                                </button>
                                <button class="btn btn-outline-light btn-sm" onclick="window.print()">
                                    <i class="bi bi-printer"></i>
                                    Print Report
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            <?php endif; ?>
        </div>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    </div>

    <!-- Progress Indicator -->
    <div class="mt-3">
        <div class="d-flex justify-content-between align-items-center mb-2">
            <small class="text-muted">Overall System Health</small>
            <small class="text-muted">
                <?php echo $summary['passed']; ?>/<?php echo $summary['total']; ?> requirements met
            </small>
        </div>
        <div class="progress" style="height: 8px;">
            <?php 
            $successRate = $summary['total'] > 0 ? ($summary['passed'] / $summary['total']) * 100 : 0;
            $warningRate = $summary['total'] > 0 ? ($summary['warnings'] / $summary['total']) * 100 : 0;
            $errorRate = $summary['total'] > 0 ? ($summary['failed'] / $summary['total']) * 100 : 0;
            ?>
            <div class="progress-bar bg-success" role="progressbar" 
                 style="width: <?php echo $successRate; ?>%" 
                 title="<?php echo $summary['passed']; ?> passed"></div>
            <div class="progress-bar bg-warning" role="progressbar" 
                 style="width: <?php echo $warningRate; ?>%" 
                 title="<?php echo $summary['warnings']; ?> warnings"></div>
            <div class="progress-bar bg-danger" role="progressbar" 
                 style="width: <?php echo $errorRate; ?>%" 
                 title="<?php echo $summary['failed']; ?> failed"></div>
        </div>
    </div>
</div>

<script>
function scrollToFirstError() {
    const firstError = document.querySelector('.requirement-item.failed');
    if (firstError) {
        firstError.scrollIntoView({ behavior: 'smooth', block: 'center' });
        firstError.style.animation = 'highlight 2s ease-in-out';
    }
}

function scrollToFirstWarning() {
    const firstWarning = document.querySelector('.requirement-item.warning');
    if (firstWarning) {
        firstWarning.scrollIntoView({ behavior: 'smooth', block: 'center' });
        firstWarning.style.animation = 'highlight 2s ease-in-out';
    }
}
</script>

<style>
.alert-icon {
    opacity: 0.8;
}

.alert-actions ul {
    padding-left: 1.2rem;
}

.alert-actions li {
    margin-bottom: 0.25rem;
}

@keyframes highlight {
    0% { background-color: transparent; }
    50% { background-color: rgba(255, 193, 7, 0.3); }
    100% { background-color: transparent; }
}
</style>