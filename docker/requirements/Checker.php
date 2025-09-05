<?php

declare(strict_types=1);

final class Checker
{
    private $result;
    private $buildType;
    private $phpVersion;
    private $systemInfo;

    public function __construct()
    {
        $this->buildType = getenv('BUILD_TYPE') ?: 'unknown';
        $this->phpVersion = PHP_VERSION;
        $this->initSystemInfo();
    }

    /**
     * Initialize system information
     */
    private function initSystemInfo()
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
     * Get system uptime
     */
    private function getUptime()
    {
        if (file_exists('/proc/uptime')) {
            $uptime = file_get_contents('/proc/uptime');
            $uptime = (float) explode(' ', $uptime)[0];
            return $this->formatUptime($uptime);
        }
        return 'Unknown';
    }

    /**
     * Format uptime in human readable format
     */
    private function formatUptime($seconds)
    {
        $days = floor($seconds / 86400);
        $hours = floor(($seconds % 86400) / 3600);
        $minutes = floor(($seconds % 3600) / 60);

        return sprintf('%dd %dh %dm', $days, $hours, $minutes);
    }

    /**
     * Check requirements based on build type
     */
    public function check($requirements = null)
    {
        if ($requirements === null) {
            $requirements = $this->getDefaultRequirements();
        }

        if (is_string($requirements)) {
            $requirements = require $requirements;
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
    private function processRequirement(&$requirement)
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
    private function normalizeRequirement($requirement)
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
    private function runPerformanceTest($testType)
    {
        switch ($testType) {
            case 'opcache':
                return $this->getOpcacheMetrics();
            case 'memory':
                return $this->getMemoryMetrics();
            case 'extensions':
                return $this->getExtensionMetrics();
            default:
                return null;
        }
    }

    /**
     * Get OPcache metrics
     */
    private function getOpcacheMetrics()
    {
        if (!$this->checkOpcacheLoaded() || !function_exists('opcache_get_status')) {
            return null;
        }

        $status = opcache_get_status(false);
        if (!$status) {
            return null;
        }

        $metrics = [
            'enabled' => $status['opcache_enabled'],
            'memory_usage' => round($status['memory_usage']['used_memory'] / 1024 / 1024, 2) . ' MB',
            'memory_free' => round($status['memory_usage']['free_memory'] / 1024 / 1024, 2) . ' MB',
            'memory_wasted' => round($status['memory_usage']['wasted_memory'] / 1024 / 1024, 2) . ' MB',
            'cached_files' => $status['opcache_statistics']['num_cached_scripts'],
            'max_cached_files' => ini_get('opcache.max_accelerated_files'),
            'hit_rate' => round($status['opcache_statistics']['opcache_hit_rate'], 2) . '%',
            'cache_misses' => $status['opcache_statistics']['misses'],
            'cache_hits' => $status['opcache_statistics']['hits']
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
                $metrics['jit_buffer_used'] = round($status['jit']['buffer_size'] / 1024 / 1024, 2) . ' MB';
                $metrics['jit_compiled_funcs'] = $status['jit']['num_traces'];
            }
        } else {
            $metrics['jit_enabled'] = false;
        }

        return $metrics;
    }

    /**
     * Get memory metrics
     */
    private function getMemoryMetrics()
    {
        return [
            'current_usage' => round(memory_get_usage(true) / 1024 / 1024, 2) . ' MB',
            'peak_usage' => round(memory_get_peak_usage(true) / 1024 / 1024, 2) . ' MB',
            'limit' => ini_get('memory_limit')
        ];
    }

    /**
     * Get extension metrics
     */
    private function getExtensionMetrics()
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
    private function getDefaultRequirements()
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
                    'performance_test' => 'opcache'
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
                    'description' => 'Just-In-Time compilation for enhanced performance in PHP 8.0+',
                    'recommendation' => 'Enable JIT with opcache.jit=tracing for optimal performance'
                ],
                [
                    'name' => 'APCu Extension',
                    'condition' => extension_loaded('apcu'),
                    'mandatory' => false,
                    'description' => 'APCu user cache for application-level caching',
                    'recommendation' => 'Install php-apcu for better caching'
                ]
            ]
        ];

        // Add development-specific requirements
        if ($this->buildType === 'dev' || $this->buildType === 'full') {
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
                ],
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

        // Add full build specific requirements
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
                    'name' => 'Oracle PDO',
                    'condition' => extension_loaded('pdo_oci'),
                    'mandatory' => false,
                    'description' => 'Oracle Database connectivity via PDO',
                    'recommendation' => 'Oracle Instant Client and pdo_oci extension required'
                ],
                [
                    'name' => 'SQL Server SQLSRV',
                    'condition' => extension_loaded('sqlsrv'),
                    'mandatory' => false,
                    'description' => 'Microsoft SQL Server connectivity via SQLSRV',
                    'recommendation' => 'Microsoft ODBC Driver and sqlsrv extension required',
                    'version_info' => extension_loaded('sqlsrv') ? phpversion('sqlsrv') : null
                ],
                [
                    'name' => 'SQL Server PDO',
                    'condition' => extension_loaded('pdo_sqlsrv'),
                    'mandatory' => false,
                    'description' => 'Microsoft SQL Server connectivity via PDO',
                    'recommendation' => 'Microsoft ODBC Driver and pdo_sqlsrv extension required'
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
                ],
                [
                    'name' => 'Memcached Extension',
                    'condition' => extension_loaded('memcached'),
                    'mandatory' => false,
                    'description' => 'Memcached distributed memory caching',
                    'recommendation' => 'Install php-memcached for Memcached support'
                ]
            ];
        }

        // Add image processing
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
     * Check if OPcache is loaded (works for both extension and core versions)
     */
    public function checkOpcacheLoaded()
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
    public function checkOpcacheEnabled()
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
    public function checkOpcacheCliEnabled()
    {
        if (!$this->checkOpcacheLoaded()) {
            return false;
        }

        $enabled = ini_get('opcache.enable_cli');
        return $enabled === '1' || $enabled === 1 || $enabled === true;
    }

    /**
     * Check if JIT is enabled and configured
     */
    public function checkJitEnabled()
    {
        if (!$this->checkOpcacheLoaded()) {
            return false;
        }

        $jitSetting = ini_get('opcache.jit');
        return $jitSetting && $jitSetting !== '0' && $jitSetting !== 'disable' && $jitSetting !== 'off';
    }

    /**
     * Check if memory limit meets minimum requirement
     */
    public function checkMemoryLimit($minimumLimit)
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
    public function checkCommandExists($command)
    {
        $locator = (PHP_OS_FAMILY === 'Windows') ? 'where' : 'command -v';
        $arg = escapeshellarg($command);
        $code = 1;
        exec("$locator $arg > /dev/null 2>&1", $void, $code);

        return $code === 0;
    }

    /**
     * Compare byte sizes
     */
    public function compareByteSize($a, $b, $operator = '>=')
    {
        $bytesA = $this->getByteSize($a);
        $bytesB = $this->getByteSize($b);

        switch ($operator) {
            case '>=':
                return $bytesA >= $bytesB;
            case '>':
                return $bytesA > $bytesB;
            case '<=':
                return $bytesA <= $bytesB;
            case '<':
                return $bytesA < $bytesB;
            case '==':
                return $bytesA == $bytesB;
            default:
                return false;
        }
    }

    /**
     * Convert size string to bytes
     */
    public function getByteSize($size)
    {
        $size = trim($size);
        $last = strtolower($size[strlen($size)-1]);
        $size = (int) $size;

        switch($last) {
            case 'g':
                $size *= 1024;
            case 'm':
                $size *= 1024;
            case 'k':
                $size *= 1024;
        }

        return $size;
    }

    /**
     * Get check result
     */
    public function getResult()
    {
        return $this->result;
    }

    /**
     * Render HTML output
     */
    public function renderHtml()
    {
        if (!$this->result) {
            $this->check();
        }

        $result = $this->result;
        include __DIR__ . '/template.php';
    }

    /**
     * Get JSON output
     */
    public function getJson()
    {
        if (!$this->result) {
            $this->check();
        }

        return json_encode($this->result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    }
}
