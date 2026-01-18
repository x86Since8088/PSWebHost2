param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# UI_Uplot Status Endpoint
# Returns app health and availability

try {
    $stats = @{
        status = 'healthy'
        appName = 'UI_Uplot'
        appVersion = '1.0.0'
        timestamp = (Get-Date).ToString('o')
        features = @{
            chartCreation = $true
            dataImport = $true
            csvSupport = $true
            jsonSupport = $true
            sqlSupport = $true
            metricsIntegration = $true
        }
    }

    # Check if config endpoint is accessible (basic health check)
    $configPath = Join-Path $PSScriptRoot "..\..\config\get.ps1"
    if (Test-Path $configPath) {
        $stats.configAvailable = $true
    } else {
        $stats.configAvailable = $false
        $stats.status = 'degraded'
    }

    $jsonResponse = $stats | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'UI_Uplot' -Message "Error getting UI_Uplot status: $($_.Exception.Message)"
    $errorResponse = @{
        error = $_.Exception.Message
        status = 'error'
        appName = 'UI_Uplot'
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
