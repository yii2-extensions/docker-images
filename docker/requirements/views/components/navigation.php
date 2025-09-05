<?php

declare (strict_types=1);

/**
 * Sidebar Navigation Component
 *
 * @var array $categories
 * @var array $summary
 */
?>
<nav class="sidebar" id="sidebar">
    <div class="sidebar-header">
        <div class="sidebar-brand">
            <div class="yii-logo-small">Yii</div>
            <span class="brand-text">Requirements</span>
        </div>
        <button class="btn btn-ghost btn-sm sidebar-toggle d-lg-none" id="sidebarToggle">
            <i class="bi bi-x-lg"></i>
        </button>
    </div>
    
    <div class="sidebar-content">
        <!-- Quick Stats -->
        <div class="nav-stats">
            <div class="stat-item">
                <span class="stat-number text-success"><?php echo $summary['passed']; ?></span>
                <span class="stat-label">Passed</span>
            </div>
            <div class="stat-item">
                <span class="stat-number text-warning"><?php echo $summary['warnings']; ?></span>
                <span class="stat-label">Warnings</span>
            </div>
            <div class="stat-item">
                <span class="stat-number text-danger"><?php echo $summary['failed']; ?></span>
                <span class="stat-label">Failed</span>
            </div>
        </div>
        
        <!-- Navigation Menu -->
        <ul class="nav flex-column nav-pills">
            <li class="nav-item">
                <a class="nav-link" href="#overview" data-bs-spy="scroll">
                    <i class="bi bi-speedometer2"></i>
                    <span>Overview</span>
                </a>
            </li>
            <li class="nav-item">
                <a class="nav-link" href="#system-info" data-bs-spy="scroll">
                    <i class="bi bi-info-circle"></i>
                    <span>System Info</span>
                </a>
            </li>
            
            <?php foreach ($categories as $index => $category): ?>
            <li class="nav-item">
                <a class="nav-link" href="#category-<?php echo $index; ?>" data-bs-spy="scroll">
                    <i class="bi bi-<?php echo getCategoryIcon($category['name']); ?>"></i>
                    <span><?php echo $category['name']; ?></span>
                    <div class="nav-badges">
                        <?php if ($category['summary']['failed'] > 0): ?>
                            <span class="badge bg-danger"><?php echo $category['summary']['failed']; ?></span>
                        <?php elseif ($category['summary']['warnings'] > 0): ?>
                            <span class="badge bg-warning"><?php echo $category['summary']['warnings']; ?></span>
                        <?php else: ?>
                            <span class="badge bg-success"><i class="bi bi-check"></i></span>
                        <?php endif; ?>
                    </div>
                </a>
            </li>
            <?php endforeach; ?>
        </ul>
        
        <!-- Actions -->
        <div class="nav-actions">
            <button class="btn btn-outline-primary btn-sm w-100 mb-2" onclick="exportReport()">
                <i class="bi bi-download"></i> Export Report
            </button>
            <button class="btn btn-outline-secondary btn-sm w-100" onclick="refreshCheck()">
                <i class="bi bi-arrow-clockwise"></i> Refresh
            </button>
        </div>
    </div>
</nav>

<!-- Sidebar Overlay for Mobile -->
<div class="sidebar-overlay d-lg-none" id="sidebarOverlay"></div>

<!-- Mobile Sidebar Toggle Button -->
<button class="btn btn-primary mobile-nav-toggle d-lg-none" id="mobileNavToggle">
    <i class="bi bi-list"></i>
</button>

<?php

/**
 * Get appropriate icon for category
 */
function getCategoryIcon($categoryName) {
    $icons = [
        'Core PHP Requirements' => 'gear-fill',
        'Essential Extensions' => 'puzzle-fill',
        'Performance & Caching' => 'lightning-fill',
        'Development Tools' => 'tools',
        'Database Extensions' => 'database-fill',
        'Enterprise Database Extensions' => 'server',
        'NoSQL & Caching' => 'hdd-stack-fill',
        'Image Processing' => 'image-fill'
    ];
    
    return $icons[$categoryName] ?? 'folder-fill';
}