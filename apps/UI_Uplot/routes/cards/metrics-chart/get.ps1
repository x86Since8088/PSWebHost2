param([hashtable]$Context, [hashtable]$SessionData)

$response = @{
    status = 'success'
    component = 'metrics-chart'
    scriptPath = '/apps/UI_Uplot/public/elements/metrics-chart/component.js'
    title = 'Metrics Chart (uPlot)'
    description = 'High-performance time-series charting for PSWebHost metrics and custom data sources'
    element = @{
        id = 'metrics-chart'
        type = 'component'
        component = 'metrics-chart'
        refreshable = $true
        configurable = $true
        dataSources = @('WebHostMetrics API', 'Custom REST endpoints', 'CSV data', 'JSON data')
        features = @(
            'Real-time polling with pause/resume',
            'Configurable time windows (5m to 24h)',
            'In-browser SQL storage with sql.js',
            'Automatic data pruning and deduplication',
            '4x faster than Chart.js'
        )
    }
}

context_response -Response $Context.Response -Json ($response | ConvertTo-Json -Depth 10 -Compress)
