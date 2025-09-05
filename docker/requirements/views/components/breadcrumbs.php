<?php
/**
 * Breadcrumbs Component - Fixed version
 * @var array $categories
 */
?>
<nav class="breadcrumb-nav" aria-label="breadcrumb">
    <div class="container-fluid">
        <ol class="breadcrumb" id="dynamicBreadcrumb">
            <li class="breadcrumb-item">
                <a href="#overview" class="breadcrumb-link">
                    <i class="bi bi-house-fill"></i>
                    <span>Overview</span>
                </a>
            </li>
            <li class="breadcrumb-item active" aria-current="page" id="currentSection">
                <span>Loading...</span>
            </li>
        </ol>
        
        <!-- Section Progress -->
        <div class="section-progress">
            <div class="progress-info">
                <span class="section-counter" id="sectionCounter">1 of <?= count($categories) + 2 ?></span>
                <span class="section-title" id="sectionTitle">Overview</span>
            </div>
            <div class="progress-bar-container">
                <div class="progress progress-sm">
                    <div class="progress-bar bg-primary" id="sectionProgress" style="width: 0%"></div>
                </div>
            </div>
        </div>
        
        <!-- Navigation Controls -->
        <div class="nav-controls">
            <button class="btn btn-outline-secondary btn-sm" id="prevSection" disabled>
                <i class="bi bi-chevron-left"></i>
                <span class="d-none d-md-inline">Previous</span>
            </button>
            <button class="btn btn-outline-secondary btn-sm" id="nextSection">
                <span class="d-none d-md-inline">Next</span>
                <i class="bi bi-chevron-right"></i>
            </button>
        </div>
    </div>
</nav>

<script>
// Breadcrumb sections data
window.breadcrumbSections = [
    { id: 'overview', title: 'Overview', icon: 'speedometer2' },
    { id: 'system-info', title: 'System Information', icon: 'info-circle' }
    <?php foreach ($categories as $index => $category): ?>
    ,{ 
        id: 'category-<?= $index ?>', 
        title: '<?= ViewRenderer::escape($category['name']) ?>', 
        icon: '<?= ComponentHelper::getCategoryIcon($category['name']) ?>' 
    }
    <?php endforeach; ?>
];
</script>