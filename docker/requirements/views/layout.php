<?php

declare(strict_types=1);

/**
 * Main layout template with navigation improvements.
 * 
 * @var array $result Requirement check result
 */
$system = $result['system'];
$summary = $result['summary'];
$categories = $result['categories'];
$overallStatus = $summary['errors'] > 0 ? 'danger' : ($summary['warnings'] > 0 ? 'warning' : 'success');
?>
<!DOCTYPE html>
<html lang="en" data-bs-theme="auto">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Yii2 Requirements Checker - <?php echo ucfirst($system['build_type']); ?> Build</title>
    
    <!-- Bootstrap 5.3 CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.2/font/bootstrap-icons.css" rel="stylesheet">
    
    <!-- Application CSS -->
    <link href="assets/css/app.css" rel="stylesheet">
</head>
<body>
    <!-- Theme Toggle -->
    <div class="theme-toggle">
        <button class="btn btn-outline-secondary btn-sm" type="button" id="themeToggle">
            <i class="bi bi-sun-fill" id="themeIcon"></i>
        </button>
    </div>

    <!-- Sidebar Navigation -->
    <?php include __DIR__ . '/components/navigation.php'; ?>

    <!-- Main Content -->
    <div class="main-content">
        <!-- Sticky Header -->
        <?php include __DIR__ . '/components/header.php'; ?>
        
        <!-- Breadcrumbs -->
        <?php include __DIR__ . '/components/breadcrumbs.php'; ?>
        
        <!-- Content Container -->
        <div class="container-fluid content-wrapper">
            <!-- Summary Cards -->
            <?php include __DIR__ . '/components/summary-cards.php'; ?>
            
            <!-- Status Alert -->
            <?php include __DIR__ . '/partials/status-alert.php'; ?>
            
            <!-- System Information -->
            <?php include __DIR__ . '/components/system-info.php'; ?>
            
            <!-- Requirements by Category -->
            <?php foreach ($categories as $categoryIndex => $category): ?>
                <div id="category-<?php echo $categoryIndex; ?>">
                <!--    <?php include __DIR__ . '/components/category-section.php'; ?> 
                </div>
            <?php endforeach; ?>
            
            <!-- Footer -->
            <?php include __DIR__ . '/components/footer.php'; ?>
        </div>
    </div>

    <!-- View Mode Toggle (Compact/Expanded) -->
    <div class="view-toggle">
        <button class="btn btn-primary btn-sm" type="button" id="viewToggle">
            <i class="bi bi-list" id="viewIcon"></i>
            <span id="viewText">Compact</span>
        </button>
    </div>

    <!-- Bootstrap 5.3 JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
    
    <!-- Application JS -->
    <script src="assets/js/app.js"></script>
</body>
</html>