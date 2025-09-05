<?php

declare(strict_types=1);

/**
 * Component Helper Class
 * Provides utilities for components and UI elements
 */
class ComponentHelper
{
    /**
     * Get icon for requirement category
     */
    public static function getCategoryIcon(string $categoryName): string
    {
        $icons = [
            'Core PHP Requirements' => 'code-square',
            'Essential Extensions' => 'puzzle',
            'Performance & Caching' => 'speedometer2',
            'Development Tools' => 'tools',
            'Database Extensions' => 'database',
            'Enterprise Database Extensions' => 'server',
            'NoSQL & Caching' => 'hdd-stack',
            'Image Processing' => 'image'
        ];

        return $icons[$categoryName] ?? 'gear';
    }

    /**
     * Get status class for requirement
     */
    public static function getStatusClass(string $status): string
    {
        return match($status) {
            'passed' => 'success',
            'warning' => 'warning',
            'failed' => 'danger',
            default => 'secondary'
        };
    }

    /**
     * Get status icon for requirement
     */
    public static function getStatusIcon(string $status): string
    {
        return match($status) {
            'passed' => 'check-circle-fill',
            'warning' => 'exclamation-triangle-fill',
            'failed' => 'x-circle-fill',
            default => 'question-circle'
        };
    }

    /**
     * Get overall system status
     */
    public static function getOverallStatus(array $summary): string
    {
        if ($summary['failed'] > 0 || $summary['errors'] > 0) {
            return 'danger';
        }
        if ($summary['warnings'] > 0) {
            return 'warning';
        }
        return 'success';
    }

    /**
     * Get status message
     */
    public static function getStatusMessage(array $summary): string
    {
        $total = $summary['total'];
        $passed = $summary['passed'];
        $warnings = $summary['warnings'];
        $failed = $summary['failed'];

        if ($failed > 0) {
            return "System has {$failed} critical " . ($failed === 1 ? 'issue' : 'issues') . " that must be addressed";
        }

        if ($warnings > 0) {
            return "System meets minimum requirements but has {$warnings} optional " . ($warnings === 1 ? 'improvement' : 'improvements') . " available";
        }

        return "System meets all requirements ({$passed}/{$total} checks passed)";
    }

    /**
     * Generate badge HTML
     */
    public static function badge(string $text, string $type = 'primary', string $class = ''): string
    {
        $escapedText = ViewRenderer::escape($text);
        return "<span class='badge bg-{$type} {$class}'>{$escapedText}</span>";
    }

    /**
     * Generate progress bar HTML
     */
    public static function progressBar(float $percentage, string $type = 'primary', bool $striped = false): string
    {
        $percentage = max(0, min(100, $percentage));
        $stripedClass = $striped ? 'progress-bar-striped' : '';

        return "
        <div class='progress'>
            <div class='progress-bar bg-{$type} {$stripedClass}'
                 role='progressbar'
                 style='width: {$percentage}%'
                 aria-valuenow='{$percentage}'
                 aria-valuemin='0'
                 aria-valuemax='100'>
                {$percentage}%
            </div>
        </div>";
    }

    /**
     * Format file size
     */
    public static function formatBytes(int $bytes, int $precision = 2): string
    {
        $bytes = max(0, $bytes);
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];
        $i = 0;

        for (; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }

        return round($bytes, $precision) . ' ' . $units[$i];
    }

    /**
     * Format uptime
     */
    public static function formatUptime(int $seconds): string
    {
        $days = intval($seconds / 86400);
        $hours = intval(($seconds % 86400) / 3600);
        $minutes = intval(($seconds % 3600) / 60);

        $parts = [];
        if ($days > 0) $parts[] = $days . 'd';
        if ($hours > 0) $parts[] = $hours . 'h';
        if ($minutes > 0) $parts[] = $minutes . 'm';

        return empty($parts) ? '0m' : implode(' ', $parts);
    }
}
