param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$roles = @()
)

<#
.SYNOPSIS
    Status endpoint for WebHost Realtime Events app
.DESCRIPTION
    Returns app status, statistics, and available features
.PARAMETER Test
    Test mode - outputs to console instead of HTTP response
.PARAMETER roles
    Array of roles to use for testing authentication (when Test is enabled)
.EXAMPLE
    # Test endpoint with console output
    .\get.ps1 -Test -roles @('authenticated')
.EXAMPLE
    # Test with query parameters via URL
    /apps/WebhostRealtimeEvents/api/v1/status?test=true&roles=authenticated
#>

# Check for test mode via query parameter
if ($Request -and $Request.QueryString['test'] -eq 'true') {
    $Test = $true
}

# Parse roles from query parameter if in test mode
if ($Test -and $Request -and $Request.QueryString['roles']) {
    $roles = $Request.QueryString['roles'] -split ','
}

# Create mock sessiondata if in test mode
if ($Test) {
    if ($roles.Count -eq 0) {
        $roles = @('authenticated')  # Default to authenticated for testing
    }
    $sessiondata = @{
        Roles = $roles
        UserID = 'test-user'
        SessionID = 'test-session'
    }
}

try {
    # Get log file info
    $logFile = Join-Path $Global:PSWebServer.Project_Root.Path "Logs\PSWebHost.log"
    $logExists = Test-Path $logFile
    $logSize = if ($logExists) { (Get-Item $logFile).Length } else { 0 }

    # Check if LogHistory is available
    $logHistoryEnabled = $null -ne $Global:LogHistory
    $logHistoryCount = if ($logHistoryEnabled) { $Global:LogHistory.Count } else { 0 }

    $status = @{
        status = 'healthy'
        appName = 'WebHost Realtime Events'
        appVersion = '1.0.0'
        timestamp = (Get-Date).ToString('o')
        features = @{
            timeRangeFiltering = $true
            textSearch = $true
            categoryFiltering = $true
            severityFiltering = $true
            sourceFiltering = $true
            userFiltering = $true
            sessionFiltering = $true
            sortable = $true
            exportCSV = $true
            exportTSV = $true
            columnToggle = $true
            wordWrap = $true
            enhancedLogFormat = $true
        }
        logFile = @{
            path = $logFile
            exists = $logExists
            sizeBytes = $logSize
            sizeMB = [math]::Round($logSize / 1MB, 2)
        }
        logHistory = @{
            enabled = $logHistoryEnabled
            eventCount = $logHistoryCount
        }
        defaultTimeRange = 15  # minutes
        maxEvents = 10000
    }

    $jsonData = $status | ConvertTo-Json -Depth 5 -Compress

    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        Write-Host "Content-Type: application/json" -ForegroundColor Gray
        Write-Host "`nResponse Data:" -ForegroundColor Cyan
        $status | ConvertTo-Json -Depth 5 | Write-Host
        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "App Name: $($status.appName)" -ForegroundColor Yellow
        Write-Host "App Version: $($status.appVersion)" -ForegroundColor Yellow
        Write-Host "Status: $($status.status)" -ForegroundColor Green
        Write-Host "Log File: $($status.logFile.path)" -ForegroundColor Gray
        Write-Host "  Exists: $($status.logFile.exists)" -ForegroundColor $(if ($status.logFile.exists) { 'Green' } else { 'Red' })
        Write-Host "  Size: $($status.logFile.sizeMB) MB" -ForegroundColor Gray
        Write-Host "Enhanced Log Format: $($status.features.enhancedLogFormat)" -ForegroundColor Yellow
        return
    }

    context_response -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"
}
catch {
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace
        return
    }

    Write-PSWebHostLog -Severity Error -Category EventViewer -Message "Error getting app status: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
