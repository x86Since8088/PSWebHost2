# Quick Status Check - Fast system health verification
# Run this anytime to verify PSWebHost is healthy

param([switch]$Detailed)

$checks = @()

# Check 1: Listener
$check1 = @{
    Name = "HTTP Listener"
    Pass = $AsyncRunspacePool.ListenerInstance.IsListening
    Message = if ($AsyncRunspacePool.ListenerInstance.IsListening) {
        "Listening on port: $(($AsyncRunspacePool.ListenerInstance.Prefixes | Select-Object -First 1) -replace '.*:(\d+)/.*', '$1')"
    } else {
        "Not listening"
    }
}
$checks += $check1

# Check 2: Worker Pool
$workerCount = $AsyncRunspacePool.Workers.Count
$check2 = @{
    Name = "Worker Pool"
    Pass = $workerCount -eq 15
    Message = "$workerCount workers active"
}
$checks += $check2

# Check 3: Request Processing
$totalRequests = ($AsyncRunspacePool.Stats.Values | Measure-Object RequestCount -Sum).Sum
$check3 = @{
    Name = "Request Processing"
    Pass = $totalRequests -gt 0
    Message = "$totalRequests requests processed"
}
$checks += $check3

# Check 4: Metrics Collection
$sampleCount = $Global:PSWebServer.Metrics.Samples.Count
$hasTimestamp = -not [string]::IsNullOrEmpty($Global:PSWebServer.Metrics.Current.Timestamp)
$check4 = @{
    Name = "Metrics Collection"
    Pass = $hasTimestamp
    Message = if ($hasTimestamp) {
        "Active - Last: $($Global:PSWebServer.Metrics.Current.Timestamp)"
    } else {
        "No samples collected"
    }
}
$checks += $check4

# Check 5: Metrics Job
$job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue
$check5 = @{
    Name = "Metrics Job"
    Pass = $job -and $job.State -eq 'Running'
    Message = if ($job) { "State: $($job.State)" } else { "Not found" }
}
$checks += $check5

# Display results
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     PSWebHost Quick Status Check      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝`n" -ForegroundColor Cyan

$allPass = $true
foreach ($check in $checks) {
    $icon = if ($check.Pass) { "✓" } else { "✗"; $allPass = $false }
    $color = if ($check.Pass) { "Green" } else { "Red" }
    Write-Host "  $icon $($check.Name): " -NoNewline -ForegroundColor $color
    Write-Host $check.Message -ForegroundColor Gray
}

Write-Host ""
if ($allPass) {
    Write-Host "  🎉 All systems operational!" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Some systems need attention" -ForegroundColor Yellow
    Write-Host "  Run: . .\run_all_diagnostics.ps1 for details" -ForegroundColor Gray
}
Write-Host ""

# Detailed mode
if ($Detailed) {
    Write-Host "━━━ Detailed Status ━━━" -ForegroundColor Yellow

    # Worker states
    $states = $AsyncRunspacePool.Stats.Values | Group-Object State
    Write-Host "`nWorker States:" -ForegroundColor Cyan
    $states | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Gray
    }

    # Recent CSV files
    $metricsDir = $Global:PSWebServer.Metrics.Config.MetricsDirectory
    if ($metricsDir -and (Test-Path $metricsDir)) {
        $recentCsvs = Get-ChildItem $metricsDir -Filter '*_2026-*.csv' |
            Where-Object { ((Get-Date) - $_.LastWriteTime).TotalMinutes -lt 5 } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 5

        if ($recentCsvs) {
            Write-Host "`nRecent CSV Files (last 5 min):" -ForegroundColor Cyan
            $recentCsvs | ForEach-Object {
                $age = [int]((Get-Date) - $_.LastWriteTime).TotalSeconds
                Write-Host "  $($_.Name) (${age}s ago)" -ForegroundColor Gray
            }
        }
    }

    # Error summary
    $jobErrors = @($job.ChildJobs[0].Error)
    $stateErrors = @($Global:PSWebServer.Metrics.JobState.Errors)
    Write-Host "`nError Count:" -ForegroundColor Cyan
    Write-Host "  Job Errors: $($jobErrors.Count)" -ForegroundColor $(if ($jobErrors.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  State Errors: $($stateErrors.Count)" -ForegroundColor $(if ($stateErrors.Count -eq 0) { 'Green' } else { 'Red' })
}

return $allPass
