<?php
/**
 * Footer Component
 * @var array $system
 */
?>
<footer class="requirements-footer py-5 mt-5 border-top">
    <div class="container-fluid">
        <div class="row g-4">
            <!-- Yii Framework Branding -->
            <div class="col-lg-4">
                <div class="footer-brand">
                    <div class="d-flex align-items-center mb-3">
                        <div class="yii-logo-footer me-3">Yii</div>
                        <div>
                            <h6 class="mb-0">Yii Framework</h6>
                            <small class="text-muted">Requirements Checker</small>
                        </div>
                    </div>
                    <p class="text-muted mb-3">
                        A comprehensive system validation tool for Yii2 applications, 
                        built with modern web technologies and designed for developer productivity.
                    </p>
                    <div class="footer-links">
                        <a href="https://www.yiiframework.com/" target="_blank" class="text-decoration-none me-3">
                            <i class="bi bi-globe"></i>
                            Official Website
                        </a>
                        <a href="https://github.com/yiisoft/yii2" target="_blank" class="text-decoration-none me-3">
                            <i class="bi bi-github"></i>
                            GitHub
                        </a>
                        <a href="https://www.yiiframework.com/doc/guide/2.0/en" target="_blank" class="text-decoration-none">
                            <i class="bi bi-book"></i>
                            Documentation
                        </a>
                    </div>
                </div>
            </div>
            
            <!-- System Status -->
            <div class="col-lg-4">
                <h6 class="mb-3">System Status</h6>
                <div class="footer-stats">
                    <div class="row g-3">
                        <div class="col-6">
                            <div class="stat-card">
                                <div class="stat-icon">
                                    <i class="bi bi-server"></i>
                                </div>
                                <div class="stat-info">
                                    <div class="stat-value"><?php echo $system['build_type']; ?></div>
                                    <div class="stat-label">Build Type</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-6">
                            <div class="stat-card">
                                <div class="stat-icon">
                                    <i class="bi bi-code-square"></i>
                                </div>
                                <div class="stat-info">
                                    <div class="stat-value"><?php echo $system['php_sapi']; ?></div>
                                    <div class="stat-label">Server API</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-6">
                            <div class="stat-card">
                                <div class="stat-icon">
                                    <i class="bi bi-memory"></i>
                                </div>
                                <div class="stat-info">
                                    <div class="stat-value"><?php echo $system['memory_limit']; ?></div>
                                    <div class="stat-label">Memory Limit</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-6">
                            <div class="stat-card">
                                <div class="stat-icon">
                                    <i class="bi bi-speedometer"></i>
                                </div>
                                <div class="stat-info">
                                    <div class="stat-value"><?php echo count(get_loaded_extensions()); ?></div>
                                    <div class="stat-label">Extensions</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Actions & Tools -->
            <div class="col-lg-4">
                <h6 class="mb-3">Actions & Tools</h6>
                <div class="footer-actions">
                    <div class="action-group mb-3">
                        <h6 class="action-title">Export Options</h6>
                        <div class="btn-group-vertical w-100">
                            <button class="btn btn-outline-primary btn-sm" onclick="exportReport()">
                                <i class="bi bi-download me-2"></i>
                                Download JSON Report
                            </button>
                            <button class="btn btn-outline-secondary btn-sm" onclick="window.print()">
                                <i class="bi bi-printer me-2"></i>
                                Print This Report
                            </button>
                            <a href="?format=json" class="btn btn-outline-info btn-sm" target="_blank">
                                <i class="bi bi-file-earmark-code me-2"></i>
                                View JSON API
                            </a>
                        </div>
                    </div>
                    
                    <div class="action-group">
                        <h6 class="action-title">System Actions</h6>
                        <div class="btn-group-vertical w-100">
                            <button class="btn btn-outline-success btn-sm" onclick="refreshCheck()">
                                <i class="bi bi-arrow-clockwise me-2"></i>
                                Refresh Check
                            </button>
                            <button class="btn btn-outline-warning btn-sm" onclick="clearCache()">
                                <i class="bi bi-trash me-2"></i>
                                Clear Cache
                            </button>
                            <button class="btn btn-outline-info btn-sm" onclick="showKeyboardShortcuts()">
                                <i class="bi bi-keyboard me-2"></i>
                                Keyboard Shortcuts
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Footer Bottom -->
        <div class="row mt-4 pt-4 border-top">
            <div class="col-md-6">
                <div class="footer-info">
                    <div class="d-flex align-items-center mb-2">
                        <i class="bi bi-server me-2 text-muted"></i>
                        <span class="text-muted">
                            Server: <?php echo htmlspecialchars($system['server_software']); ?>
                        </span>
                    </div>
                    <div class="d-flex align-items-center mb-2">
                        <i class="bi bi-clock me-2 text-muted"></i>
                        <span class="text-muted">
                            Generated: <?php echo date('F j, Y \a\t g:i A T'); ?>
                        </span>
                    </div>
                    <div class="d-flex align-items-center">
                        <i class="bi bi-hash me-2 text-muted"></i>
                        <span class="text-muted">
                            Report ID: <code><?php echo substr(md5($system['timestamp'] . $system['php_version']), 0, 12); ?></code>
                        </span>
                    </div>
                </div>
            </div>
            <div class="col-md-6 text-md-end">
                <div class="footer-credits">
                    <p class="mb-2">
                        <span class="text-muted">Powered by </span>
                        <a href="https://www.yiiframework.com/" target="_blank" class="text-decoration-none fw-bold text-primary">
                            Yii Framework
                        </a>
                    </p>
                    <p class="mb-2">
                        <span class="text-muted">Built with </span>
                        <a href="https://getbootstrap.com/" target="_blank" class="text-decoration-none">
                            Bootstrap 5.3
                        </a>
                        <span class="text-muted"> & </span>
                        <a href="https://icons.getbootstrap.com/" target="_blank" class="text-decoration-none">
                            Bootstrap Icons
                        </a>
                    </p>
                    <p class="mb-0">
                        <i class="bi bi-docker me-1 text-muted"></i>
                        <span class="text-muted">Docker Image Architecture</span>
                    </p>
                </div>
            </div>
        </div>
        
        <!-- Copyright -->
        <div class="row mt-3 pt-3 border-top">
            <div class="col-12 text-center">
                <small class="text-muted">
                    © <?php echo date('Y'); ?> Yii Software LLC. 
                    Requirements Checker v2.0 - 
                    <a href="https://github.com/yiisoft/yii2/blob/master/LICENSE.md" target="_blank" class="text-decoration-none">
                        BSD License
                    </a>
                </small>
            </div>
        </div>
    </div>
</footer>

<!-- Keyboard Shortcuts Modal -->
<div class="modal fade" id="keyboardShortcutsModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">
                    <i class="bi bi-keyboard me-2"></i>
                    Keyboard Shortcuts
                </h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <div class="row g-3">
                    <div class="col-12">
                        <h6>Navigation</h6>
                        <ul class="list-unstyled">
                            <li><kbd>Alt</kbd> + <kbd>←</kbd> - Previous section</li>
                            <li><kbd>Alt</kbd> + <kbd>→</kbd> - Next section</li>
                        </ul>
                    </div>
                    <div class="col-12">
                        <h6>Actions</h6>
                        <ul class="list-unstyled">
                            <li><kbd>Ctrl</kbd> + <kbd>D</kbd> - Toggle view mode</li>
                            <li><kbd>Ctrl</kbd> + <kbd>E</kbd> - Export report</li>
                            <li><kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> - Toggle theme</li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
function clearCache() {
    if (confirm('Clear browser cache for this page? This will refresh the page.')) {
        // Clear localStorage
        localStorage.removeItem('theme');
        localStorage.removeItem('viewMode');
        
        // Force refresh with cache bypass
        window.location.reload(true);
    }
}

function showKeyboardShortcuts() {
    const modal = new bootstrap.Modal(document.getElementById('keyboardShortcutsModal'));
    modal.show();
}

// Auto-hide footer on scroll (optional)
let lastScrollTop = 0;
const footer = document.querySelector('.requirements-footer');

window.addEventListener('scroll', function() {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    
    if (scrollTop > lastScrollTop && scrollTop > 200) {
        // Scrolling down
        footer.style.transform = 'translateY(20px)';
        footer.style.opacity = '0.8';
    } else {
        // Scrolling up
        footer.style.transform = 'translateY(0)';
        footer.style.opacity = '1';
    }
    
    lastScrollTop = scrollTop;
});
</script>

<style>
.requirements-footer {
    background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
    transition: all 0.3s ease;
}

[data-bs-theme="dark"] .requirements-footer {
    background: linear-gradient(135deg, #1e1e1e 0%, #2d2d2d 100%);
}

.yii-logo-footer {
    width: 45px;
    height: 45px;
    background: linear-gradient(135deg, var(--yii-primary) 0%, var(--yii-secondary) 100%);
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 18px;
    color: white;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

.footer-links a {
    color: #6c757d;
    font-size: 0.9rem;
    transition: color 0.2s ease;
}

.footer-links a:hover {
    color: var(--yii-primary);
}

.stat-card {
    display: flex;
    align-items: center;
    padding: 0.75rem;
    background: rgba(255, 255, 255, 0.5);
    border-radius: 8px;
    border: 1px solid rgba(0, 0, 0, 0.05);
    transition: all 0.2s ease;
}

.stat-card:hover {
    background: rgba(255, 255, 255, 0.8);
    transform: translateY(-1px);
}

[data-bs-theme="dark"] .stat-card {
    background: rgba(255, 255, 255, 0.05);
    border-color: rgba(255, 255, 255, 0.1);
}

[data-bs-theme="dark"] .stat-card:hover {
    background: rgba(255, 255, 255, 0.1);
}

.stat-icon {
    margin-right: 0.5rem;
    color: var(--yii-primary);
    font-size: 1.1rem;
}

.stat-value {
    font-weight: 600;
    font-size: 0.9rem;
    line-height: 1;
}

.stat-label {
    font-size: 0.7rem;
    color: #6c757d;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.action-group {
    margin-bottom: 1rem;
}

.action-title {
    font-size: 0.85rem;
    color: #6c757d;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 0.5rem;
}

.footer-info .d-flex {
    font-size: 0.9rem;
}

.footer-credits {
    font-size: 0.9rem;
}

.footer-credits a {
    color: var(--yii-primary);
}

kbd {
    background-color: #f8f9fa;
    border: 1px solid #dee2e6;
    border-radius: 3px;
    padding: 2px 4px;
    font-size: 0.8rem;
}

[data-bs-theme="dark"] kbd {
    background-color: #495057;
    border-color: #6c757d;
    color: #fff;
}
</style>