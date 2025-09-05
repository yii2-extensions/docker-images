<?php

declare(strict_types=1);

/**
 * View Renderer Class
 * Handles template rendering with proper separation of concerns
 */
class ViewRenderer
{
    private static array $viewPaths = [
        'layouts' => __DIR__ . '/../views/layouts',
        'components' => __DIR__ . '/../views/components',
        'partials' => __DIR__ . '/../views/partials'
    ];
    
    private static array $globalData = [];
    
    /**
     * Set global data available to all views
     */
    public static function setGlobalData(array $data): void
    {
        self::$globalData = array_merge(self::$globalData, $data);
    }
    
    /**
     * Render a layout with data
     */
    public static function renderLayout(string $layout, array $data = []): string
    {
        return self::render('layouts', $layout, $data);
    }
    
    /**
     * Render a component with data
     */
    public static function renderComponent(string $component, array $data = []): string
    {
        return self::render('components', $component, $data);
    }
    
    /**
     * Render a partial with data
     */
    public static function renderPartial(string $partial, array $data = []): string
    {
        return self::render('partials', $partial, $data);
    }
    
    /**
     * Core render method
     */
    private static function render(string $type, string $template, array $data = []): string
    {
        $filePath = self::$viewPaths[$type] . '/' . $template . '.php';
        
        if (!file_exists($filePath)) {
            throw new RuntimeException("View file not found: {$filePath}");
        }
        
        // Merge global data with local data
        $viewData = array_merge(self::$globalData, $data);
        
        // Extract variables to make them available in the template
        extract($viewData, EXTR_SKIP);
        
        // Start output buffering
        ob_start();
        
        try {
            include $filePath;
            return ob_get_clean();
        } catch (Throwable $e) {
            ob_end_clean();
            throw new RuntimeException("Error rendering {$type}/{$template}: " . $e->getMessage(), 0, $e);
        }
    }
    
    /**
     * Safe HTML output with escaping
     */
    public static function escape(string $text): string
    {
        return htmlspecialchars($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }
    
    /**
     * Format number with proper locale
     */
    public static function formatNumber(int|float $number, int $decimals = 0): string
    {
        return number_format($number, $decimals);
    }
    
    /**
     * Format percentage
     */
    public static function formatPercent(float $value, int $decimals = 1): string
    {
        return number_format($value, $decimals) . '%';
    }
}