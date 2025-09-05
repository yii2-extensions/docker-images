document.addEventListener('DOMContentLoaded', function() {
    // === THEME TOGGLE ===
    const themeToggle = document.getElementById('themeToggle');
    const themeIcon = document.getElementById('themeIcon');
    const html = document.documentElement;
    
    // Initialize theme
    const savedTheme = localStorage.getItem('theme') || 'auto';
    html.setAttribute('data-bs-theme', savedTheme);
    updateThemeIcon(savedTheme);
    
    themeToggle?.addEventListener('click', function() {
        const currentTheme = html.getAttribute('data-bs-theme');
        let newTheme = currentTheme === 'light' ? 'dark' : 
                      currentTheme === 'dark' ? 'auto' : 'light';
        
        html.setAttribute('data-bs-theme', newTheme);
        localStorage.setItem('theme', newTheme);
        updateThemeIcon(newTheme);
    });
    
    function updateThemeIcon(theme) {
        const icons = {
            'light': 'bi-sun-fill',
            'dark': 'bi-moon-fill',
            'auto': 'bi-circle-half'
        };
        if (themeIcon) {
            themeIcon.className = `bi ${icons[theme] || icons.auto}`;
        }
    }

    // === VIEW MODE TOGGLE ===
    const viewToggle = document.getElementById('viewToggle');
    const viewIcon = document.getElementById('viewIcon');
    const viewText = document.getElementById('viewText');
    let isCompactMode = localStorage.getItem('viewMode') === 'compact';
    
    // Initialize view mode
    updateViewMode();
    
    viewToggle?.addEventListener('click', function() {
        isCompactMode = !isCompactMode;
        updateViewMode();
        localStorage.setItem('viewMode', isCompactMode ? 'compact' : 'expanded');
    });
    
    function updateViewMode() {
        document.body.classList.toggle('compact-mode', isCompactMode);
        if (viewIcon && viewText) {
            viewIcon.className = isCompactMode ? 'bi bi-grid' : 'bi bi-list';
            viewText.textContent = isCompactMode ? 'Expanded' : 'Compact';
        }
    }

    // === MOBILE SIDEBAR ===
    const sidebar = document.getElementById('sidebar');
    const sidebarOverlay = document.getElementById('sidebarOverlay');
    const mobileNavToggle = document.getElementById('mobileNavToggle');
    const sidebarToggle = document.getElementById('sidebarToggle');
    
    function toggleSidebar() {
        sidebar?.classList.toggle('show');
        sidebarOverlay?.classList.toggle('show');
    }
    
    mobileNavToggle?.addEventListener('click', toggleSidebar);
    sidebarToggle?.addEventListener('click', toggleSidebar);
    sidebarOverlay?.addEventListener('click', toggleSidebar);

    // === SMOOTH SCROLLING & NAVIGATION ===
    const sections = window.breadcrumbSections || [];
    let currentSectionIndex = 0;
    
    // Navigation link clicks
    document.querySelectorAll('a[data-bs-spy="scroll"]').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const targetId = this.getAttribute('href').substring(1);
            scrollToSection(targetId);
            
            // Close mobile sidebar if open
            if (window.innerWidth < 992) {
                toggleSidebar();
            }
        });
    });
    
    // Previous/Next navigation
    const prevBtn = document.getElementById('prevSection');
    const nextBtn = document.getElementById('nextSection');
    
    prevBtn?.addEventListener('click', () => {
        if (currentSectionIndex > 0) {
            currentSectionIndex--;
            scrollToSection(sections[currentSectionIndex].id);
        }
    });
    
    nextBtn?.addEventListener('click', () => {
        if (currentSectionIndex < sections.length - 1) {
            currentSectionIndex++;
            scrollToSection(sections[currentSectionIndex].id);
        }
    });
    
    function scrollToSection(sectionId) {
        const element = document.getElementById(sectionId);
        if (element) {
            const headerHeight = document.querySelector('.sticky-header')?.offsetHeight || 0;
            const breadcrumbHeight = document.querySelector('.breadcrumb-nav')?.offsetHeight || 0;
            const offset = headerHeight + breadcrumbHeight + 20;
            
            const elementPosition = element.offsetTop - offset;
            
            window.scrollTo({
                top: elementPosition,
                behavior: 'smooth'
            });
        }
    }

    // === SCROLL SPY & BREADCRUMB UPDATES ===
    let isScrolling = false;
    
    window.addEventListener('scroll', throttle(function() {
        updateActiveSection();
        updateScrollProgress();
    }, 100));
    
    function updateActiveSection() {
        const scrollPos = window.scrollY;
        const headerHeight = document.querySelector('.sticky-header')?.offsetHeight || 0;
        const breadcrumbHeight = document.querySelector('.breadcrumb-nav')?.offsetHeight || 0;
        const offset = headerHeight + breadcrumbHeight + 100;
        
        let activeIndex = 0;
        
        sections.forEach((section, index) => {
            const element = document.getElementById(section.id);
            if (element && element.offsetTop - offset <= scrollPos) {
                activeIndex = index;
            }
        });
        
        currentSectionIndex = activeIndex;
        updateBreadcrumb(activeIndex);
        updateNavigationControls(activeIndex);
        updateSidebarActiveState(activeIndex);
    }
    
    function updateBreadcrumb(index) {
        const currentSection = document.getElementById('currentSection');
        const sectionCounter = document.getElementById('sectionCounter');
        const sectionTitle = document.getElementById('sectionTitle');
        const sectionProgress = document.getElementById('sectionProgress');
        
        if (sections[index]) {
            const section = sections[index];
            
            if (currentSection) {
                currentSection.innerHTML = `<i class="bi bi-${section.icon}"></i> ${section.title}`;
            }
            
            if (sectionCounter) {
                sectionCounter.textContent = `${index + 1} of ${sections.length}`;
            }
            
            if (sectionTitle) {
                sectionTitle.textContent = section.title;
            }
            
            if (sectionProgress) {
                const progress = ((index + 1) / sections.length) * 100;
                sectionProgress.style.width = `${progress}%`;
            }
        }
    }
    
    function updateNavigationControls(index) {
        if (prevBtn) {
            prevBtn.disabled = index === 0;
        }
        if (nextBtn) {
            nextBtn.disabled = index === sections.length - 1;
        }
    }
    
    function updateSidebarActiveState(index) {
        // Remove active class from all nav links
        document.querySelectorAll('.nav-link').forEach(link => {
            link.classList.remove('active');
        });
        
        // Add active class to current section
        if (sections[index]) {
            const activeLink = document.querySelector(`a[href="#${sections[index].id}"]`);
            activeLink?.classList.add('active');
        }
    }
    
    function updateScrollProgress() {
        const scrolled = window.scrollY;
        const maxHeight = document.documentElement.scrollHeight - window.innerHeight;
        const progress = (scrolled / maxHeight) * 100;
        
        // Update any global scroll indicators here if needed
    }

    // === UTILITY FUNCTIONS ===
    function throttle(func, limit) {
        let inThrottle;
        return function() {
            const args = arguments;
            const context = this;
            if (!inThrottle) {
                func.apply(context, args);
                inThrottle = true;
                setTimeout(() => inThrottle = false, limit);
            }
        }
    }

    // === EXPORT FUNCTIONALITY ===
    window.exportReport = function() {
        const reportData = {
            timestamp: new Date().toISOString(),
            system: window.systemData || {},
            summary: window.summaryData || {},
            categories: window.categoriesData || []
        };
        
        // JSON Export
        const dataStr = JSON.stringify(reportData, null, 2);
        const dataBlob = new Blob([dataStr], {type: 'application/json'});
        const url = URL.createObjectURL(dataBlob);
        
        const link = document.createElement('a');
        link.href = url;
        link.download = `yii2-requirements-${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    };

    // === REFRESH FUNCTIONALITY ===
    window.refreshCheck = function() {
        // Show loading state
        const refreshBtns = document.querySelectorAll('[onclick="refreshCheck()"]');
        refreshBtns.forEach(btn => {
            btn.innerHTML = '<i class="bi bi-arrow-clockwise spin"></i> Refreshing...';
            btn.disabled = true;
        });
        
        // Reload page after short delay
        setTimeout(() => {
            window.location.reload();
        }, 1000);
    };

    // === KEYBOARD SHORTCUTS ===
    document.addEventListener('keydown', function(e) {
        // Navigate with arrow keys
        if (e.key === 'ArrowLeft' && e.altKey) {
            e.preventDefault();
            prevBtn?.click();
        } else if (e.key === 'ArrowRight' && e.altKey) {
            e.preventDefault();
            nextBtn?.click();
        }
        
        // Toggle view mode with Ctrl/Cmd + D
        if (e.key === 'd' && (e.ctrlKey || e.metaKey)) {
            e.preventDefault();
            viewToggle?.click();
        }
        
        // Toggle theme with Ctrl/Cmd + Shift + T
        if (e.key === 't' && (e.ctrlKey || e.metaKey) && e.shiftKey) {
            e.preventDefault();
            themeToggle?.click();
        }
        
        // Export with Ctrl/Cmd + E
        if (e.key === 'e' && (e.ctrlKey || e.metaKey)) {
            e.preventDefault();
            exportReport();
        }
    });

    // === INITIALIZE ON LOAD ===
    setTimeout(() => {
        updateActiveSection();
        updateBreadcrumb(0);
        updateNavigationControls(0);
    }, 500);

    // === AUTO REFRESH (optional) ===
    let autoRefreshInterval;
    const AUTO_REFRESH_MINUTES = 5;
    
    function startAutoRefresh() {
        autoRefreshInterval = setInterval(() => {
            // Subtle indication that refresh is available
            const header = document.querySelector('.sticky-header');
            if (header) {
                header.style.animation = 'pulse 1s ease-in-out';
                setTimeout(() => {
                    header.style.animation = '';
                }, 1000);
            }
        }, AUTO_REFRESH_MINUTES * 60 * 1000);
    }
    
    // Uncomment to enable auto-refresh
    // startAutoRefresh();
    
    // Clean up on page unload
    window.addEventListener('beforeunload', () => {
        if (autoRefreshInterval) {
            clearInterval(autoRefreshInterval);
        }
    });
});

// === CSS ANIMATION HELPERS ===
const style = document.createElement('style');
style.textContent = `
    .spin {
        animation: spin 1s linear infinite;
    }
    
    @keyframes spin {
        from { transform: rotate(0deg); }
        to { transform: rotate(360deg); }
    }
`;
document.head.appendChild(style);