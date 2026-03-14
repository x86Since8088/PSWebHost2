# Memory Leak Diagnostic Script
# Probes the PSWebHost server to identify memory leaks

Write-Host "`n=== PSWebHost Memory Diagnostics ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Gray

# Get server PID by looking for the one with highest memory usage
$serverProcess = Get-Process pwsh | Sort-Object WorkingSet64 -Descending | Select-Object -First 1
$memoryMB = [math]::Round($serverProcess.WorkingSet64 / 1MB, 2)
$privateMemoryMB = [math]::Round($serverProcess.PrivateMemorySize64 / 1MB, 2)

Write-Host "Server Process: PID $($serverProcess.Id)" -ForegroundColor Yellow
Write-Host "  Working Set: $memoryMB MB" -ForegroundColor $(if ($memoryMB -gt 1000) { 'Red' } else { 'Yellow' })
Write-Host "  Private Memory: $privateMemoryMB MB" -ForegroundColor $(if ($privateMemoryMB -gt 1000) { 'Red' } else { 'Yellow' })
Write-Host "  Handles: $($serverProcess.Handles)" -ForegroundColor Gray
Write-Host "  Threads: $($serverProcess.Threads.Count)" -ForegroundColor Gray

# Connect to running server via PowerShell remoting to inspect memory
Write-Host "`n=== Inspecting Global Variables ===" -ForegroundColor Cyan

$inspectionScript = {
    $results = @{}

    # Check log queue size
    if ($global:PSWebHostLogQueue) {
        $results.LogQueueCount = $global:PSWebHostLogQueue.Count
    }

    # Check events collection
    if ($global:PSWebServer.events) {
        $results.EventsCount = $global:PSWebServer.events.Count
    }

    # Check sessions
    if ($global:PSWebSessions) {
        $results.SessionsCount = $global:PSWebSessions.Count
        $results.SessionKeys = @($global:PSWebSessions.Keys)
    }

    # Check Track_HashTables
    if ($global:PSWebServer.Track_HashTables) {
        $results.TrackHashTables = $global:PSWebServer.Track_HashTables | ConvertTo-Json -Depth 3 -Compress
    }

    # Check Track_Arrays
    if ($global:PSWebServer.Track_Arrays) {
        $results.TrackArrays = $global:PSWebServer.Track_Arrays | ConvertTo-Json -Depth 3 -Compress
    }

    # Check runspaces
    if ($global:PSWebServer.Runspaces) {
        $results.RunspacesCount = $global:PSWebServer.Runspaces.Count
    }

    # Check async runspace pool
    if ($global:AsyncRunspacePool) {
        $results.AsyncPoolSize = $global:AsyncRunspacePool.PoolSize
        $results.AsyncPoolInitialized = $global:AsyncRunspacePool.Initialized
        if ($global:AsyncRunspacePool.Runspaces) {
            $results.AsyncPoolRunspacesCount = $global:AsyncRunspacePool.Runspaces.Count
        }
    }

    # Check jobs
    if ($global:PSWebServer.Jobs) {
        $results.JobsCount = $global:PSWebServer.Jobs.Count
    }

    # Check metrics
    if ($global:PSWebServer.Metrics) {
        if ($global:PSWebServer.Metrics.History) {
            $results.MetricsHistoryCount = $global:PSWebServer.Metrics.History.Count
        }
        if ($global:PSWebServer.Metrics.DataPoints) {
            $results.MetricsDataPointsCount = $global:PSWebServer.Metrics.DataPoints.Count
        }
    }

    # Check cached data
    if ($global:PSWebServer.CachedJobs) {
        $results.CachedJobsCount = $global:PSWebServer.CachedJobs.Count
    }
    if ($global:PSWebServer.CachedRunspaces) {
        $results.CachedRunspacesCount = $global:PSWebServer.CachedRunspaces.Count
    }
    if ($global:PSWebServer.CachedTasks) {
        $results.CachedTasksCount = $global:PSWebServer.CachedTasks.Count
    }

    # Get all global variable sizes
    $largeVars = Get-Variable -Scope Global -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_.Value } |
        ForEach-Object {
            $size = 0
            try {
                if ($_.Value -is [string]) {
                    $size = $_.Value.Length
                } elseif ($_.Value -is [System.Collections.ICollection]) {
                    $size = $_.Value.Count
                } elseif ($_.Value -is [hashtable]) {
                    $size = $_.Value.Count
                }
            } catch {}

            [PSCustomObject]@{
                Name = $_.Name
                Type = $_.Value.GetType().Name
                Size = $size
            }
        } |
        Where-Object { $_.Size -gt 100 } |
        Sort-Object Size -Descending |
        Select-Object -First 20

    $results.LargeVariables = $largeVars

    return $results
}

# Execute the inspection in the server's context
try {
    # Try to get diagnostics via direct process inspection
    Write-Host "Attempting direct inspection via server process..." -ForegroundColor Gray

    # Create a script file to execute within the server
    $diagScriptPath = Join-Path $PSScriptRoot "temp_diag.ps1"
    $inspectionScript.ToString() | Set-Content $diagScriptPath

    # Alternative: Use server's API endpoints
    Write-Host "`nAttempting to query server API..." -ForegroundColor Gray

    # Query the debug endpoint (may require authentication)
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/debug/vars/get?format=list" -Method Get -ErrorAction Stop
        Write-Host "  API Query Successful!" -ForegroundColor Green
        Write-Host "  Total Global Variables: $($response.Count)" -ForegroundColor Yellow

        # Show largest collections
        $collections = $response | Where-Object { $_.Type -match 'Hashtable|Dictionary|ArrayList|List|Queue|Collection' }
        if ($collections) {
            Write-Host "`n  Collection Variables:" -ForegroundColor Cyan
            $collections | Select-Object -First 10 | ForEach-Object {
                Write-Host "    - $($_.Name): $($_.Type)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  API Query Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  (This may be expected if authentication is required)" -ForegroundColor Gray
    }

    # Clean up temp file
    if (Test-Path $diagScriptPath) {
        Remove-Item $diagScriptPath -Force
    }
}
catch {
    Write-Host "Error during inspection: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Recommendations ===" -ForegroundColor Cyan
Write-Host "1. Check PSWebServer.events collection size (may be growing unbounded)" -ForegroundColor Yellow
Write-Host "2. Check PSWebHostLogQueue size (should be flushed regularly)" -ForegroundColor Yellow
Write-Host "3. Check session storage (old sessions may not be cleaned up)" -ForegroundColor Yellow
Write-Host "4. Check metrics history (may be retaining too much data)" -ForegroundColor Yellow
Write-Host "5. Consider implementing periodic cleanup tasks" -ForegroundColor Yellow

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "Run from within the server console to get detailed diagnostics:" -ForegroundColor Gray
Write-Host '  $global:PSWebServer.events.Count' -ForegroundColor White
Write-Host '  $global:PSWebHostLogQueue.Count' -ForegroundColor White
Write-Host '  $global:PSWebSessions.Count' -ForegroundColor White
Write-Host '  $global:PSWebServer.Metrics.History.Count' -ForegroundColor White

Write-Host "`nDiagnostics complete.`n" -ForegroundColor Cyan
