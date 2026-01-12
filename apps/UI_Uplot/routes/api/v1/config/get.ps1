#Requires -Version 7

<#
.SYNOPSIS
    Get UI_Uplot app configuration
.DESCRIPTION
    Returns app configuration including ConsoleToAPILoggingLevel and other settings
#>

param($Request, $Response, $Session)

try {
    # Get app configuration from app.yaml
    $appRoot = $Global:PSWebServer['UI_Uplot']['AppRoot']
    $appYamlPath = Join-Path $appRoot 'app.yaml'

    if (-not (Test-Path $appYamlPath)) {
        throw "App configuration file not found: $appYamlPath"
    }

    # Parse YAML configuration
    # Note: This is a simplified YAML parser - for production use a proper YAML module
    $yamlContent = Get-Content $appYamlPath -Raw

    # Extract settings section
    $config = @{
        name = 'uPlot Chart Builder'
        version = '1.0.0'
        settings = @{
            ConsoleToAPILoggingLevel = 'info'
            defaultChartHeight = 400
            defaultChartWidth = 800
            defaultRefreshInterval = 5
            maxDataPoints = 1000
            enableRealTimeUpdates = $true
        }
        chartTypes = @(
            @{ id = 'time-series'; name = 'Time Series'; icon = 'chart-line' }
            @{ id = 'area-chart'; name = 'Area Chart'; icon = 'chart-area' }
            @{ id = 'bar-chart'; name = 'Bar Chart'; icon = 'chart-bar' }
            @{ id = 'scatter-plot'; name = 'Scatter Plot'; icon = 'circle' }
            @{ id = 'multi-axis'; name = 'Multi-Axis Chart'; icon = 'chart-gantt' }
            @{ id = 'heatmap'; name = 'Heatmap'; icon = 'th' }
        )
        dataSources = @(
            @{ id = 'rest-json'; name = 'REST API (JSON)' }
            @{ id = 'rest-csv'; name = 'REST API (CSV)' }
            @{ id = 'sql-js'; name = 'SQL.js Query' }
            @{ id = 'metrics-db'; name = 'Metrics Database' }
            @{ id = 'static-json'; name = 'Static JSON' }
            @{ id = 'upload-csv'; name = 'Upload CSV' }
        )
    }

    # Try to parse ConsoleToAPILoggingLevel from YAML if available
    if ($yamlContent -match 'ConsoleToAPILoggingLevel:\s*(\w+)') {
        $config.settings.ConsoleToAPILoggingLevel = $matches[1]
    }

    # Return configuration as JSON
    $Response.ContentType = 'application/json'
    $Response.Write(($config | ConvertTo-Json -Depth 10))

} catch {
    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
