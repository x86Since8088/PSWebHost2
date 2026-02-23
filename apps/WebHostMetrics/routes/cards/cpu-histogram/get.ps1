param([hashtable]$Context, [hashtable]$SessionData)

$response = @{
    status = 'success'
    component = 'cpu-histogram'
    scriptPath = '/apps/WebHostMetrics/public/elements/cpu-histogram/component.js'
    title = 'CPU Usage History'
    element = @{
        id = 'cpu-histogram'
        type = 'component'
        component = 'cpu-histogram'
        refreshable = $true
    }
}

# Include current CPU data if available
try {
    if ($Global:PSWebServer.Metrics.Current) {
        $currentMetrics = $Global:PSWebServer.Metrics.Current

        if ($currentMetrics.cpu) {
            $response.cpu = $currentMetrics.cpu
        }

        if ($currentMetrics.timestamp) {
            $response.timestamp = $currentMetrics.timestamp
        }

        if ($currentMetrics.hostname) {
            $response.hostname = $currentMetrics.hostname
        }
    }
} catch {
    # If metrics not available, just return component metadata
    Write-Verbose "[cpu-histogram] Metrics not available: $_"
}

context_response -Response $Context.Response -Json ($response | ConvertTo-Json -Depth 10 -Compress)
