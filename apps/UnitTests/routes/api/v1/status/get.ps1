param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# UnitTests Status Endpoint
# Returns app health and test runner availability

try {
    $stats = @{
        status = 'healthy'
        appName = 'UnitTests'
        appVersion = '1.0.0'
        timestamp = (Get-Date).ToString('o')
        features = @{
            testRunner = $true
            coverageReporting = $true
            processMonitoring = $true
        }
    }

    # Check if test runner endpoints are accessible
    $testListPath = Join-Path $PSScriptRoot "..\tests\list\get.ps1"
    if (Test-Path $testListPath) {
        $stats.testListAvailable = $true
    } else {
        $stats.testListAvailable = $false
        $stats.status = 'degraded'
    }

    $jsonResponse = $stats | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'UnitTests' -Message "Error getting UnitTests status: $($_.Exception.Message)"
    $errorResponse = @{
        error = $_.Exception.Message
        status = 'error'
        appName = 'UnitTests'
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
