<?php

declare(strict_types=1);

/**
 * Requirements Checker Class
 * Improved version with proper error handling and deprecation fixes
 */
class RequirementsChecker
{
    private array $result = [];
    private string $buildType;
    private string $phpVersion;
    private array $systemInfo = [];

    public function __construct()
    {
        $this->buildType = getenv('BUILD_TYPE') ?: 'unknown';
        $this->phpVersion = PHP_VERSION;
        $this->initSystemInfo();
    }

    /**
     * Initialize system information
     */
    private function initSystemInfo(): void
    {
        $this->systemInfo = [
            'php_version' => $this->phpVersion,
            'php_sapi' => php_sapi_name(),
            'build_type' => $this->buildType,
            'environment' => getenv('YII_ENV') ?: 'unknown',
            'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
            'os' => php_uname('s') . ' ' . php_uname('r'),
            'architecture' => php_uname('m'),
            'memory_limit' => ini_get('memory_limit'),
            'max_execution_time' => ini_get('max_execution_time'),
            'timestamp' => date('c'),
            'uptime' => $this->getUptime()
        ];
    }

    /**
     * Get system uptime (fixed version)
     */
    private function getUptime(): string
    {
        try {
            if (PHP_OS_FAMILY === 'Linux' && file_exists('/proc/uptime')) {
                $uptime = file_get_contents('/proc/uptime');
                if ($uptime !== false) {
                    $uptime = (float) explode(' ', $uptime)[0];
                    return $this->formatUptime($uptime);
                }
            }
        } catch (Throwable $e) {
            // Silently fail for uptime detection
        }
        
        return 'Unknown';
    }

    /**
     * Format uptime in human readable format
     */
    private function formatUptime(float $seconds): string
    {
        $days = intdiv((int)$seconds, 86400);
        $hours = intdiv((int)$seconds % 86400, 3600);
        $minutes = intdiv((int)$seconds % 3600, 60);
        
        return sprintf('%dd %dh %dm', $days, $hours, $minutes);
    }

    /**
     * Check requirements based on build type
     */
    public function check(?array $requirements = null): self
    {
        if ($requirements === null) {
            $requirements = $this->getDefaultRequirements();
        }

        $this->result = [
            'system' => $this->systemInfo,
            'summary' => [
                'total' => 0,
                'passed' => 0,
                'failed' => 0,
                'warnings' => 0,
                'errors' => 0
            ],
            'categories' => []
        ];

        foreach ($requirements as $categoryName => $categoryRequirements) {
            $category = [
                'name' => $categoryName,
                'requirements' => [],
                'summary' => ['total' => 0, 'passed' => 0, 'failed' => 0, 'warnings' => 0]
            ];

            foreach ($categoryRequirements as $requirement) {
                $normalizedReq = $this->normalizeRequirement($requirement);
                $this->processRequirement($normalizedReq);
                
                $category['requirements'][] = $normalizedReq;
                $category['summary']['total']++;
                
                if ($normalizedReq['condition']) {
                    $category['summary']['passed']++;
                    $this->result['summary']['passed']++;
                } else {
                    if ($normalizedReq['mandatory']) {
                        $category['summary']['failed']++;
                        $this->result['summary']['failed']++;
                        $this->result['summary']['errors']++;
                    } else {
                        $category['summary']['warnings']++;
                        $this->result['summary']['warnings']++;
                    }
                }
                
                $this->result['summary']['total']++;
            }

            $this->result['categories'][] = $category;
        }

        return $this;
    }

    /**
     * Process individual requirement
     */
    private function processRequirement(array &$requirement): void
    {
        // No need for eval processing anymore - all conditions are direct boolean values
        
        $requirement['status'] = $requirement['condition'] ? 'passed' : 
            ($requirement['mandatory'] ? 'failed' : 'warning');
        
        // Add performance metrics for certain checks
        if (isset($requirement['performance_test'])) {
            $requirement['metrics'] = $this->runPerformanceTest($requirement['performance_test']);
        }
    }

    /**
     * Normalize requirement structure
     */
    private function normalizeRequirement(array $requirement): array
    {
        return array_merge([
            'name' => 'Unknown Requirement',
            'condition' => false,
            'mandatory' => false,
            'description' => '',
            'recommendation' => '',
            'version_info' => null,
            'performance_test' => null
        ], $requirement);
    }

    /**
     * Run performance test
     */
    private function runPerformanceTest(string $testType): ?array
    {
        return match($testType) {
            'opcache' => $this->getOpcacheMetrics(),
            'memory' => $this->getMemoryMetrics(),
            'extensions' => $this->getExtensionMetrics(),
            default => null
        };
    }

    /**
     * Get OPcache metrics (enhanced version with JIT)
     */
    private function getOpcacheMetrics(): ?array
    {
        try {
            if (!extension_loaded('opcache') || !function_exists('opcache_get_status')) {
                return null;
            }

            $status = opcache_get_status(false);
            if (!$status) {
                return null;
            }

            $metrics = [
                'enabled' => $status['opcache_enabled'] ?? false,
                'memory_usage' => isset($status['memory_usage']['used_memory']) 
                    ? round($status['memory_usage']['used_memory'] / 1024 / 1024, 2) . ' MB' 
                    : 'Unknown',
                'memory_free' => isset($status['memory_usage']['free_memory']) 
                    ? round($status['memory_usage']['free_memory'] / 1024 / 1024, 2) . ' MB' 
                    : 'Unknown',
                'memory_wasted' => isset($status['memory_usage']['wasted_memory']) 
                    ? round($status['memory_usage']['wasted_memory'] / 1024 / 1024, 2) . ' MB' 
                    : 'Unknown',
                'cached_files' => $status['opcache_statistics']['num_cached_scripts'] ?? 0,
                'max_cached_files' => ini_get('opcache.max_accelerated_files'),
                'hit_rate' => isset($status['opcache_statistics']['opcache_hit_rate']) 
                    ? round($status['opcache_statistics']['opcache_hit_rate'], 2) . '%' 
                    : '0%',
                'cache_misses' => $status['opcache_statistics']['misses'] ?? 0,
                'cache_hits' => $status['opcache_statistics']['hits'] ?? 0
            ];

            // Add JIT information if available
            $jitEnabled = ini_get('opcache.jit');
            if ($jitEnabled && $jitEnabled !== '0' && $jitEnabled !== 'disable') {
                $metrics['jit_enabled'] = true;
                $metrics['jit_mode'] = ini_get('opcache.jit');
                $metrics['jit_buffer_size'] = ini_get('opcache.jit_buffer_size');
                $metrics['jit_hot_loop'] = ini_get('opcache.jit_hot_loop');
                $metrics['jit_hot_func'] = ini_get('opcache.jit_hot_func');
                
                // JIT statistics if available
                if (isset($status['jit'])) {
                    $metrics['jit_buffer_used'] = isset($status['jit']['buffer_size']) 
                        ? round($status['jit']['buffer_size'] / 1024 / 1024, 2) . ' MB'
                        : 'Unknown';
                    $metrics['jit_compiled_funcs'] = $status['jit']['num_traces'] ?? 0;
                }
            } else {
                $metrics['jit_enabled'] = false;
            }

            return $metrics;
        } catch (Throwable $e) {
            return null;
        }
    }

    /**
     * Get memory metrics
     */
    private function getMemoryMetrics(): array
    {
        return [
            'current_usage' => round(memory_get_usage(true) / 1024 / 1024, 2) . ' MB',
            'peak_usage' => round(memory_get_peak_usage(true) / 1024 / 1024, 2) . ' MB',
            'limit' => ini_get('memory_limit') ?: 'Unknown'
        ];
    }

    /**
     * Get extension metrics
     */
    private function getExtensionMetrics(): array
    {
        $extensions = get_loaded_extensions();
        $core = ['Core', 'date', 'libxml', 'pcre', 'unicode', 'filter', 'SPL', 'session', 'standard'];
        
        return [
            'total' => count($extensions),
            'core' => count(array_intersect($extensions, $core)),
            'additional' => count($extensions) - count(array_intersect($extensions, $core))
        ];
    }

    /**
     * Get default requirements based on build type
     */
    private function getDefaultRequirements(): array
    {
        $requirements = [
            'Core PHP Requirements' => [
                [
                    'name' => 'PHP Version',
                    'condition' => version_compare(PHP_VERSION, '8.1.0', '>='),
                    'mandatory' => true,
                    'description' => 'PHP 8.1.0 or higher is required for optimal performance and security',
                    'recommendation' => 'Upgrade to PHP 8.1 for better JIT compilation and performance',
                    'version_info' => PHP_VERSION
                ],
                [
                    'name' => 'Memory Limit',
                    'condition' => $this->checkMemoryLimit('256M'),
                    'mandatory' => true,
                    'description' => 'Adequate memory limit for application execution',
                    'recommendation' => 'Set memory_limit to at least 256M for production',
                    'version_info' => ini_get('memory_limit')
                ]
            ],
            'Essential Extensions' => [
                [
                    'name' => 'PDO Extension',
                    'condition' => extension_loaded('pdo'),
                    'mandatory' => true,
                    'description' => 'PHP Data Objects extension for database connectivity',
                    'recommendation' => 'Install php-pdo package'
                ],
                [
                    'name' => 'MBString Extension',
                    'condition' => extension_loaded('mbstring'),
                    'mandatory' => true,
                    'description' => 'Multibyte string handling for international characters',
                    'recommendation' => 'Install php-mbstring package'
                ],
                [
                    'name' => 'Intl Extension',
                    'condition' => extension_loaded('intl'),
                    'mandatory' => true,
                    'description' => 'Internationalization functions for locale support',
                    'recommendation' => 'Install php-intl package'
                ],
                [
                    'name' => 'OpenSSL Extension',
                    'condition' => extension_loaded('openssl'),
                    'mandatory' => true,
                    'description' => 'OpenSSL functions for cryptographic operations',
                    'recommendation' => 'Install php-openssl package'
                ],
                [
                    'name' => 'Ctype Extension',
                    'condition' => extension_loaded('ctype'),
                    'mandatory' => true,
                    'description' => 'Character type checking functions',
                    'recommendation' => 'Install php-ctype package'
                ],
                [
                    'name' => 'JSON Extension',
                    'condition' => extension_loaded('json'),
                    'mandatory' => true,
                    'description' => 'JavaScript Object Notation support',
                    'recommendation' => 'Install php-json package'
                ]
            ],
            'Performance & Caching' => [
                [
                    'name' => 'OPcache Extension',
                    'condition' => $this->checkOpcacheLoaded(),
                    'mandatory' => false,
                    'description' => 'Zend OPcache for improved performance (integrated in PHP 8.0+)',
                    'recommendation' => 'OPcache is part of PHP core since 8.0+, ensure it is enabled',
                    'performance_test' => 'opcache',
                    'version_info' => $this->getOpcacheVersion()
                ],
                [
                    'name' => 'OPcache Enabled',
                    'condition' => $this->checkOpcacheEnabled(),
                    'mandatory' => false,
                    'description' => 'OPcache is enabled and configured for opcode caching',
                    'recommendation' => 'Set opcache.enable=1 in php.ini for production performance'
                ],
                [
                    'name' => 'OPcache CLI Enabled',
                    'condition' => $this->checkOpcacheCliEnabled(),
                    'mandatory' => false,
                    'description' => 'OPcache is enabled for CLI SAPI',
                    'recommendation' => 'Set opcache.enable_cli=1 for CLI script performance'
                ],
                [
                    'name' => 'JIT Compilation',
                    'condition' => $this->checkJitEnabled(),
                    'mandatory' => false,
                    'description' => 'Just-In-Time compilation for enhanced performance',
                    'recommendation' => 'Enable JIT for PHP 8.0+ with opcache.jit=tracing',
                    'version_info' => ini_get('opcache.jit') ?: 'disabled'
                ],
                [
                    'name' => 'APCu Extension',
                    'condition' => extension_loaded('apcu'),
                    'mandatory' => false,
                    'description' => 'APCu user cache for application-level caching',
                    'recommendation' => 'Install php-apcu for better user data caching'
                ]
            ]
        ];

        // Add build-specific requirements
        if (in_array($this->buildType, ['dev', 'full'])) {
            $requirements['Development Tools'] = [
                [
                    'name' => 'Xdebug Extension',
                    'condition' => extension_loaded('xdebug'),
                    'mandatory' => false,
                    'description' => 'Xdebug for debugging and profiling',
                    'recommendation' => 'Install php-xdebug for development',
                    'version_info' => extension_loaded('xdebug') ? phpversion('xdebug') : null
                ],
                [
                    'name' => 'Composer Available',
                    'condition' => $this->checkCommandExists('composer'),
                    'mandatory' => false,
                    'description' => 'Composer dependency manager',
                    'recommendation' => 'Install Composer for dependency management'
                ]
            ];
        }

        // Add database extensions
        $requirements['Database Extensions'] = [
            [
                'name' => 'MySQL/MariaDB (PDO)',
                'condition' => extension_loaded('pdo_mysql'),
                'mandatory' => false,
                'description' => 'MySQL/MariaDB database connectivity via PDO',
                'recommendation' => 'Install php-mysql for MySQL support'
            ],
            [
                'name' => 'PostgreSQL (PDO)',
                'condition' => extension_loaded('pdo_pgsql'),
                'mandatory' => false,
                'description' => 'PostgreSQL database connectivity via PDO',
                'recommendation' => 'Install php-pgsql for PostgreSQL support'
            ],
            [
                'name' => 'SQLite (PDO)',
                'condition' => extension_loaded('pdo_sqlite'),
                'mandatory' => false,
                'description' => 'SQLite database connectivity via PDO',
                'recommendation' => 'Install php-sqlite3 for SQLite support'
            ]
        ];

        if ($this->buildType === 'full') {
            $requirements['Enterprise Database Extensions'] = [
                [
                    'name' => 'Oracle OCI8',
                    'condition' => extension_loaded('oci8'),
                    'mandatory' => false,
                    'description' => 'Oracle Database connectivity via OCI8',
                    'recommendation' => 'Oracle Instant Client and oci8 extension required',
                    'version_info' => extension_loaded('oci8') ? phpversion('oci8') : null
                ],
                [
                    'name' => 'SQL Server SQLSRV',
                    'condition' => extension_loaded('sqlsrv'),
                    'mandatory' => false,
                    'description' => 'Microsoft SQL Server connectivity via SQLSRV',
                    'recommendation' => 'Microsoft ODBC Driver and sqlsrv extension required',
                    'version_info' => extension_loaded('sqlsrv') ? phpversion('sqlsrv') : null
                ]
            ];

            $requirements['NoSQL & Caching'] = [
                [
                    'name' => 'MongoDB Extension',
                    'condition' => extension_loaded('mongodb'),
                    'mandatory' => false,
                    'description' => 'MongoDB NoSQL database support',
                    'recommendation' => 'Install php-mongodb for MongoDB support'
                ],
                [
                    'name' => 'Redis Extension',
                    'condition' => extension_loaded('redis'),
                    'mandatory' => false,
                    'description' => 'Redis in-memory data structure store',
                    'recommendation' => 'Install php-redis for Redis support'
                ]
            ];
        }

        $requirements['Image Processing'] = [
            [
                'name' => 'GD Extension',
                'condition' => extension_loaded('gd'),
                'mandatory' => false,
                'description' => 'GD graphics library for image processing',
                'recommendation' => 'Install php-gd for image manipulation'
            ],
            [
                'name' => 'ImageMagick Extension',
                'condition' => extension_loaded('imagick'),
                'mandatory' => false,
                'description' => 'ImageMagick for advanced image processing',
                'recommendation' => 'Install php-imagick for advanced image features'
            ]
        ];

        return $requirements;
    }

    /**
     * Check if memory limit meets minimum requirement
     */
    public function checkMemoryLimit(string $minimumLimit): bool
    {
        $memoryLimit = ini_get('memory_limit');
        if ($memoryLimit === '-1') {
            return true; // Unlimited
        }
        
        return $this->compareByteSize($memoryLimit, $minimumLimit, '>=');
    }

    /**
     * Check if command exists in PATH
     */
    public function checkCommandExists(string $command): bool
    {
        try {
            $whereIsCommand = (PHP_OS_FAMILY === 'Windows') ? 'where' : 'which';
            exec("$whereIsCommand $command", $output, $returnCode);
            return $returnCode === 0;
        } catch (Throwable $e) {
            return false;
        }
    }

    /**
     * Compare byte sizes
     */
    public function compareByteSize(string $a, string $b, string $operator = '>='): bool
    {
        $bytesA = $this->getByteSize($a);
        $bytesB = $this->getByteSize($b);
        
        return match($operator) {
            '>=' => $bytesA >= $bytesB,
            '>' => $bytesA > $bytesB,
            '<=' => $bytesA <= $bytesB,
            '<' => $bytesA < $bytesB,
            '==' => $bytesA == $bytesB,
            default => false
        };
    }

    /**
     * Convert size string to bytes
     */
    public function getByteSize(string $size): int
    {
        $size = trim($size);
        if (empty($size)) return 0;
        
        $last = strtolower($size[strlen($size)-1]);
        $size = (int) $size;
        
        switch($last) {
            case 'g':
                $size *= 1024;
                // fall through
            case 'm':
                $size *= 1024;
                // fall through
            case 'k':
                $size *= 1024;
        }
        
        return $size;
    }

    /**
     * Check if OPcache is loaded (works for both extension and core versions)
     */
    public function checkOpcacheLoaded(): bool
    {
        // In PHP 8.0+, OPcache is part of core but still shows as extension
        // Check multiple ways to ensure detection
        return extension_loaded('opcache') || 
               extension_loaded('Zend OPcache') || 
               function_exists('opcache_get_status') ||
               function_exists('opcache_get_configuration');
    }

    /**
     * Check if OPcache is enabled
     */
    public function checkOpcacheEnabled(): bool
    {
        if (!$this->checkOpcacheLoaded()) {
            return false;
        }
        
        $enabled = ini_get('opcache.enable');
        return $enabled === '1' || $enabled === 1 || $enabled === true;
    }

    /**
     * Check if OPcache CLI is enabled
     */
    public function checkOpcacheCliEnabled(): bool
    {
        if (!$this->checkOpcacheLoaded()) {
            return false;
        }
        
        $enabled = ini_get('opcache.enable_cli');
        return $enabled === '1' || $enabled === 1 || $enabled === true;
    }

    /**
     * Get OPcache version information
     */
    public function getOpcacheVersion(): ?string
    {
        if (!$this->checkOpcacheLoaded()) {
            return null;
        }
        
        // Try to get version from phpversion
        $version = phpversion('opcache');
        if ($version) {
            return $version;
        }
        
        // Try to get from configuration
        if (function_exists('opcache_get_configuration')) {
            $config = opcache_get_configuration();
            if (isset($config['version']['version'])) {
                return $config['version']['version'];
            }
        }
        
        // Fallback to PHP version for integrated OPcache
        return 'Integrated with PHP ' . PHP_VERSION;
    }

    /**
     * Check if JIT is enabled and configured
     */
    public function checkJitEnabled(): bool
    {
        if (!$this->checkOpcacheLoaded()) {
            return false;
        }
        
        $jitSetting = ini_get('opcache.jit');
        return $jitSetting && $jitSetting !== '0' && $jitSetting !== 'disable' && $jitSetting !== 'off';
    }

    /**
     * Evaluate PHP expression safely
     */
    private function evaluateExpression(string $expression): bool
    {
        try {
            return (bool) eval("return $expression;");
        } catch (Throwable $e) {
            return false;
        }
    }

    /**
     * Get check result
     */
    public function getResult(): array
    {
        return $this->result;
    }

    /**
     * Get JSON output
     */
    public function getJson(): string
    {
        if (empty($this->result)) {
            $this->check();
        }
        
        return json_encode($this->result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    }
}