<?php
/**
 * Main layout template - completely separated from logic
 *
 * @var array $result Requirement check result
 * @var array $system System information
 * @var array $summary Summary statistics
 * @var array $categories Requirement categories
 * @var string $overallStatus Overall system status
 */

$overallStatus = ComponentHelper::getOverallStatus($summary);
$statusMessage = ComponentHelper::getStatusMessage($summary);
$successRate = $summary['total'] > 0 ? round(($summary['passed'] / $summary['total']) * 100, 1) : 0;
?>
<!DOCTYPE html>
<html lang="en" data-bs-theme="auto">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Yii2 Requirements Checker - <?= ViewRenderer::escape(ucfirst($system['build_type'])) ?> Build</title>

    <!-- Bootstrap 5.3 CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-sRIl4kxILFvY47J16cr9ZwB07vP4J8+LH7qKQnuqkuIAvNWLzeN8tE5YBujZqJLB" crossorigin="anonymous">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.13.1/font/bootstrap-icons.min.css">

    <!-- Custom Styles -->
    <style>
        :root {
            --yii-primary: #1e88e5;
            --yii-secondary: #26a69a;
            --yii-success: #43a047;
            --yii-warning: #fb8c00;
            --yii-danger: #e53935;
            --sidebar-width: 280px;
            --header-height: 100px;
            --transition-speed: 0.3s;
        }

        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background-color: #f8f9fa;
            padding-left: var(--sidebar-width);
            padding-top: var(--header-height);
            transition: padding-left var(--transition-speed) ease;
        }

        [data-bs-theme="dark"] body {
            background-color: #121212;
        }

        /* Sidebar */
        .sidebar {
            position: fixed;
            top: 0;
            left: 0;
            width: var(--sidebar-width);
            height: 100vh;
            background: linear-gradient(135deg, var(--yii-primary) 0%, var(--yii-secondary) 100%);
            color: white;
            z-index: 1030;
            padding: 2rem 1rem;
            overflow-y: auto;
        }

        .sidebar-brand {
            display: flex;
            align-items: center;
            gap: 1rem;
            margin-bottom: 2rem;
        }

        .yii-logo {
            width: 50px;
            height: 50px;
            background: white;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 700;
            font-size: 20px;
            color: var(--yii-primary);
        }

        .brand-text h4 {
            margin: 0;
            font-weight: 600;
        }

        .brand-text small {
            opacity: 0.8;
        }

        /* Header */
        .main-header {
            position: fixed;
            top: 0;
            left: var(--sidebar-width);
            right: 0;
            height: var(--header-height);
            background: white;
            border-bottom: 1px solid #e9ecef;
            z-index: 1020;
            display: flex;
            align-items: center;
            padding: 0 2rem;
            transition: left var(--transition-speed) ease;
        }

        [data-bs-theme="dark"] .main-header {
            background: #1e1e1e;
            border-bottom-color: #333;
        }

        .header-title h1 {
            margin: 0;
            font-size: 1.75rem;
            font-weight: 600;
        }

        .header-status {
            margin-left: auto;
            display: flex;
            align-items: center;
            gap: 1rem;
        }

        .status-indicator {
            width: 50px;
            height: 50px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.5rem;
            color: white;
        }

        .status-indicator.status-success { background: var(--yii-success); }
        .status-indicator.status-warning { background: var(--yii-warning); }
        .status-indicator.status-danger { background: var(--yii-danger); }

        /* Content */
        .main-content {
            padding: 2rem;
            min-height: calc(100vh - var(--header-height));
        }

        .metric-card {
            transition: all 0.3s ease;
            cursor: pointer;
        }

        .metric-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15) !important;
        }

        .metric-icon {
            font-size: 2.5rem;
        }

        .metric-value {
            font-size: 2.5rem;
            font-weight: 700;
            line-height: 1;
        }

        /* Navigation */
        .nav-pills .nav-link {
            color: rgba(255, 255, 255, 0.8);
            border-radius: 8px;
            padding: 0.75rem 1rem;
            margin-bottom: 0.25rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
            transition: all var(--transition-speed) ease;
        }

        .nav-pills .nav-link:hover {
            background: rgba(255, 255, 255, 0.15);
            color: white;
        }

        .nav-pills .nav-link.active {
            background: rgba(255, 255, 255, 0.2);
            color: white;
        }

        /* Theme toggle */
        .theme-toggle {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 1040;
        }

        /* Responsive */
        @media (max-width: 991.98px) {
            body {
                padding-left: 0;
            }

            .sidebar {
                transform: translateX(-100%);
            }

            .sidebar.show {
                transform: translateX(0);
            }

            .main-header {
                left: 0;
            }
        }

        /* Requirement items */
        .requirement-item {
            border-left: 4px solid #e9ecef;
            transition: all 0.3s ease;
        }

        .requirement-item.status-passed {
            border-left-color: var(--yii-success);
        }

        .requirement-item.status-warning {
            border-left-color: var(--yii-warning);
        }

        .requirement-item.status-failed {
            border-left-color: var(--yii-danger);
        }

        .requirement-item:hover {
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }

        /* Stats overview */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 1rem;
            margin-bottom: 2rem;
            padding: 1rem;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 12px;
        }

        .stat-item {
            text-align: center;
        }

        .stat-number {
            display: block;
            font-size: 1.5rem;
            font-weight: 700;
        }

        .stat-label {
            font-size: 0.75rem;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <!-- Theme Toggle -->
    <div class="theme-toggle">
        <button class="btn btn-outline-secondary btn-sm" type="button" id="themeToggle">
            <i class="bi bi-sun-fill" id="themeIcon"></i>
        </button>
    </div>

    <!-- Sidebar -->
    <div class="sidebar">
        <div class="sidebar-brand">
            <div class="yii-logo">Yii</div>
            <div class="brand-text">
                <h4>Requirements</h4>
                <small><?= ViewRenderer::escape(ucfirst($system['build_type'])) ?> Build</small>
            </div>
        </div>

        <!-- Quick Stats -->
        <div class="stats-grid">
            <div class="stat-item">
                <span class="stat-number"><?= ViewRenderer::formatNumber($summary['total']) ?></span>
                <span class="stat-label">Total</span>
            </div>
            <div class="stat-item">
                <span class="stat-number text-success"><?= ViewRenderer::formatNumber($summary['passed']) ?></span>
                <span class="stat-label">Passed</span>
            </div>
            <div class="stat-item">
                <span class="stat-number text-warning"><?= ViewRenderer::formatNumber($summary['warnings']) ?></span>
                <span class="stat-label">Warnings</span>
            </div>
        </div>

        <!-- Navigation -->
        <nav class="nav nav-pills flex-column">
            <a class="nav-link active" href="#overview">
                <i class="bi bi-speedometer2"></i>
                <span>Overview</span>
            </a>
            <a class="nav-link" href="#system-info">
                <i class="bi bi-info-circle"></i>
                <span>System Info</span>
            </a>
            <?php foreach ($categories as $index => $category): ?>
            <a class="nav-link" href="#category-<?= $index ?>">
                <i class="bi bi-<?= ComponentHelper::getCategoryIcon($category['name']) ?>"></i>
                <span><?= ViewRenderer::escape($category['name']) ?></span>
                <span class="badge bg-light text-dark ms-auto"><?= $category['summary']['total'] ?></span>
            </a>
            <?php endforeach; ?>
        </nav>

        <!-- Export Actions -->
        <div class="mt-4 pt-3 border-top border-light border-opacity-25">
            <div class="d-grid gap-2">
                <button class="btn btn-outline-light btn-sm" onclick="exportReport()">
                    <i class="bi bi-download"></i> Export Report
                </button>
                <button class="btn btn-outline-light btn-sm" onclick="window.location.reload()">
                    <i class="bi bi-arrow-clockwise"></i> Refresh
                </button>
            </div>
        </div>
    </div>

    <!-- Main Header -->
    <div class="main-header">
        <div class="header-title">
            <h1>System Requirements Check</h1>
            <small class="text-muted"><?= ViewRenderer::escape($statusMessage) ?></small>
        </div>

        <div class="header-status">
            <div class="status-indicator status-<?= $overallStatus ?>">
                <i class="bi bi-<?= ComponentHelper::getStatusIcon($overallStatus === 'success' ? 'passed' : ($overallStatus === 'warning' ? 'warning' : 'failed')) ?>"></i>
            </div>
            <div class="status-text">
                <div class="fw-bold"><?= ViewRenderer::formatPercent($successRate) ?></div>
                <small class="text-muted">Success Rate</small>
            </div>
        </div>
    </div>

    <!-- Main Content -->
    <div class="main-content">
        <!-- Summary Cards -->
        <div id="overview" class="mb-5">
            <?= ViewRenderer::renderComponent('summary-cards', compact('summary')) ?>
        </div>

        <!-- System Information -->
        <div id="system-info" class="mb-5">
            <?= ViewRenderer::renderComponent('system-info', compact('system')) ?>
        </div>

        <!-- Requirements by Category -->
        <?php foreach ($categories as $index => $category): ?>
        <div id="category-<?= $index ?>" class="mb-5">
            <?= ViewRenderer::renderComponent('category-section', ['category' => $category, 'index' => $index]) ?>
        </div>
        <?php endforeach; ?>

        <!-- Footer -->
        <footer class="text-center py-4 mt-5 border-top">
            <small class="text-muted">
                Generated on <?= date('Y-m-d H:i:s T') ?> |
                PHP <?= ViewRenderer::escape(PHP_VERSION) ?> |
                Build: <?= ViewRenderer::escape($system['build_type']) ?>
            </small>
        </footer>
    </div>

    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>

    <!-- Custom JavaScript -->
    <script>
        // Theme toggle functionality
        const themeToggle = document.getElementById('themeToggle');
        const themeIcon = document.getElementById('themeIcon');

        themeToggle.addEventListener('click', () => {
            const currentTheme = document.documentElement.getAttribute('data-bs-theme');
            const newTheme = currentTheme === 'dark' ? 'light' : 'dark';

            document.documentElement.setAttribute('data-bs-theme', newTheme);
            themeIcon.className = newTheme === 'dark' ? 'bi bi-moon-fill' : 'bi bi-sun-fill';

            localStorage.setItem('theme', newTheme);
        });

        // Load saved theme
        const savedTheme = localStorage.getItem('theme') || 'light';
        document.documentElement.setAttribute('data-bs-theme', savedTheme);
        themeIcon.className = savedTheme === 'dark' ? 'bi bi-moon-fill' : 'bi bi-sun-fill';

        // Smooth scrolling navigation
        document.querySelectorAll('a[href^="#"]').forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const target = document.querySelector(link.getAttribute('href'));
                if (target) {
                    target.scrollIntoView({ behavior: 'smooth', block: 'start' });

                    // Update active nav
                    document.querySelectorAll('.nav-link').forEach(navLink => {
                        navLink.classList.remove('active');
                    });
                    link.classList.add('active');
                }
            });
        });

        // Export functionality
        function exportReport() {
            const data = <?= json_encode($result) ?>;
            const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `yii2-requirements-${new Date().toISOString().split('T')[0]}.json`;
            a.click();
            URL.revokeObjectURL(url);
        }

        // Metric card click handlers
        document.querySelectorAll('.metric-card').forEach(card => {
            card.addEventListener('click', () => {
                card.style.transform = 'scale(0.95)';
                setTimeout(() => {
                    card.style.transform = '';
                }, 150);
            });
        });

        // Mobile navigation
        if (window.innerWidth <= 991) {
            const sidebar = document.querySelector('.sidebar');
            const overlay = document.createElement('div');
            overlay.className = 'position-fixed top-0 start-0 w-100 h-100 bg-dark bg-opacity-50';
            overlay.style.zIndex = '1025';
            overlay.style.display = 'none';

            document.body.appendChild(overlay);

            // Add mobile toggle button
            const toggleBtn = document.createElement('button');
            toggleBtn.className = 'btn btn-primary position-fixed';
            toggleBtn.style.top = '20px';
            toggleBtn.style.left = '20px';
            toggleBtn.style.zIndex = '1040';
            toggleBtn.innerHTML = '<i class="bi bi-list"></i>';

            toggleBtn.addEventListener('click', () => {
                sidebar.classList.toggle('show');
                overlay.style.display = sidebar.classList.contains('show') ? 'block' : 'none';
            });

            overlay.addEventListener('click', () => {
                sidebar.classList.remove('show');
                overlay.style.display = 'none';
            });

            document.body.appendChild(toggleBtn);
        }
    </script>
</body>
</html>
