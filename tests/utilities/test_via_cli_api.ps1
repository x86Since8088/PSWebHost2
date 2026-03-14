# Test Via CLI API - Run diagnostics using the /api/v1/cli endpoint
# Usage: .\test_via_cli_api.ps1 -BearerToken "your-token-here"

param(
    [Parameter(Mandatory=$true)]
    [string]$BearerToken,

    [string]$ServerUrl = "http://localhost:8080",

    [int]$Timeout = 30
)

function Invoke-CLICommand {
    param(
        [string]$Script,
        [string]$Description = "Running command"
    )

    Write-Host "  $Description..." -ForegroundColor Gray

    $body = @{
        script = $Script
        timeout = $Timeout
    } | ConvertTo-Json

    $headers = @{
        'Authorization' = "Bearer $BearerToken"
        'Content-Type' = 'application/json'
    }

    try {
        $response = Invoke-WebRequest -Uri "$ServerUrl/api/v1/cli" `
            -Method POST `
            -Headers $headers `
            -Body $body `
            -TimeoutSec $Timeout `
            -UseBasicParsing

        $result = $response.Content | ConvertFrom-Json

        if ($result.status -eq 'success') {
            Write-Host "    ✓ Success" -ForegroundColor Green
            return $result.output
        } else {
            Write-Host "    ✗ Failed: $($result.message)" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "    ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

Write-Host "`n=== Testing Server via CLI API ===" -ForegroundColor Cyan
Write-Host "Server: $ServerUrl" -ForegroundColor Gray
Write-Host "Timeout: ${Timeout}s`n" -ForegroundColor Gray

# Test 1: Check AsyncRunspacePool Status
Write-Host "1. AsyncRunspacePool Status:" -ForegroundColor Yellow
$poolScript = @'
[PSCustomObject]@{
    Initialized = $AsyncRunspacePool.Initialized
    WorkerCount = $AsyncRunspacePool.Workers.Count
    StopRequested = $AsyncRunspacePool.StopRequested
    ListenerActive = $AsyncRunspacePool.ListenerInstance.IsListening
} | ConvertTo-Json
'@
$output = Invoke-CLICommand -Script $poolScript -Description "Checking pool status"
if ($output) {
    $output | ConvertFrom-Json | Format-List
}

# Test 2: Check Worker States
Write-Host "`n2. Worker States:" -ForegroundColor Yellow
$workerScript = @'
$AsyncRunspacePool.Stats.Values | ForEach-Object {
    [PSCustomObject]@{
        State = $_.State
        RequestCount = $_.RequestCount
        Errors = $_.Errors
    }
} | Group-Object State | ForEach-Object {
    [PSCustomObject]@{
        State = $_.Name
        Count = $_.Count
    }
} | ConvertTo-Json
'@
$output = Invoke-CLICommand -Script $workerScript -Description "Checking worker states"
if ($output) {
    $output | ConvertFrom-Json | Format-Table -AutoSize
}

# Test 3: Check Metrics Collection
Write-Host "`n3. Metrics Collection:" -ForegroundColor Yellow
$metricsScript = @'
[PSCustomObject]@{
    ConfigDir = $Global:PSWebServer.Metrics.Config.MetricsDirectory
    SampleCount = $Global:PSWebServer.Metrics.Samples.Count
    CurrentTimestamp = $Global:PSWebServer.Metrics.Current.Timestamp
    LastCollection = $Global:PSWebServer.Metrics.JobState.LastCollection
    JobState = (Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue).State
} | ConvertTo-Json
'@
$output = Invoke-CLICommand -Script $metricsScript -Description "Checking metrics collection"
if ($output) {
    $output | ConvertFrom-Json | Format-List
}

# Test 4: Check Recent CSV Files
Write-Host "`n4. Recent CSV Files:" -ForegroundColor Yellow
$csvScript = @'
$dir = $Global:PSWebServer.Metrics.Config.MetricsDirectory
if ($dir -and (Test-Path $dir)) {
    Get-ChildItem $dir -Filter '*_2026-*.csv' -ErrorAction SilentlyContinue |
        Where-Object { ((Get-Date) - $_.LastWriteTime).TotalMinutes -lt 5 } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Size = $_.Length
                Age = [int]((Get-Date) - $_.LastWriteTime).TotalSeconds
            }
        } | ConvertTo-Json
} else {
    '[]' | ConvertTo-Json
}
'@
$output = Invoke-CLICommand -Script $csvScript -Description "Checking recent CSV files"
if ($output) {
    $files = $output | ConvertFrom-Json
    if ($files.Count -gt 0) {
        $files | Format-Table -AutoSize
    } else {
        Write-Host "    No recent CSV files found" -ForegroundColor Yellow
    }
}

# Test 5: Run Metrics Collection Test
Write-Host "`n5. Force Metrics Collection:" -ForegroundColor Yellow
$collectScript = @'
$beforeCount = $Global:PSWebServer.Metrics.Samples.Count
$snapshot = Get-SystemMetricsSnapshot
Update-CurrentMetrics -Snapshot $snapshot
Add-MetricsSample -Snapshot $snapshot
$afterCount = $Global:PSWebServer.Metrics.Samples.Count

[PSCustomObject]@{
    BeforeCount = $beforeCount
    AfterCount = $afterCount
    Success = $afterCount -gt $beforeCount
    CurrentTimestamp = $Global:PSWebServer.Metrics.Current.Timestamp
} | ConvertTo-Json
'@
$output = Invoke-CLICommand -Script $collectScript -Description "Testing manual collection"
if ($output) {
    $result = $output | ConvertFrom-Json
    $result | Format-List

    if ($result.Success) {
        Write-Host "    ✓ Manual collection works!" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Manual collection failed" -ForegroundColor Red
    }
}

# Test 6: Check for stuck workers
Write-Host "`n6. Worker Activity Details:" -ForegroundColor Yellow
$activityScript = @'
$AsyncRunspacePool.Workers.Values | ForEach-Object {
    $stats = $AsyncRunspacePool.Stats[$_.RunspaceInfo.Index]
    [PSCustomObject]@{
        Index = $_.RunspaceInfo.Index
        State = $stats.State
        Availability = $_.RunspaceInfo.Runspace.RunspaceAvailability
        Requests = $stats.RequestCount
        LastRequest = $stats.LastRequest
        IsCompleted = $_.AsyncHandle.IsCompleted
    }
} | Select-Object -First 5 | ConvertTo-Json
'@
$output = Invoke-CLICommand -Script $activityScript -Description "Checking worker activity"
if ($output) {
    $output | ConvertFrom-Json | Format-Table -AutoSize
}

Write-Host "`n=== Test Complete ===`n" -ForegroundColor Cyan
Write-Host "For full diagnostics from server console, run:" -ForegroundColor Yellow
Write-Host "  . .\run_all_diagnostics.ps1" -ForegroundColor Cyan
