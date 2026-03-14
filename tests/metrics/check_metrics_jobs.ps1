#Requires -Version 7

<#
.SYNOPSIS
    Diagnostic script to check PSWebHost_MetricsCollection job status
#>

Write-Host "`n=== Metrics Job Diagnostic ===" -ForegroundColor Cyan

# Check for running jobs
$metricsJobs = Get-Job | Where-Object { $_.Name -like '*Metrics*' }

if ($metricsJobs) {
    Write-Host "`nFound $($metricsJobs.Count) metrics-related jobs:" -ForegroundColor Yellow
    $metricsJobs | Format-Table Id, Name, State, PSBeginTime, PSEndTime -AutoSize

    foreach ($job in $metricsJobs) {
        Write-Host "`n--- Job ID $($job.Id): $($job.Name) ---" -ForegroundColor Cyan
        Write-Host "State: $($job.State)" -ForegroundColor $(if ($job.State -eq 'Running') { 'Green' } else { 'Yellow' })
        Write-Host "Started: $($job.PSBeginTime)"

        # Get recent output
        $output = Receive-Job -Job $job -Keep
        if ($output) {
            Write-Host "`nRecent Output (last 10 lines):" -ForegroundColor Gray
            $output | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
    }
} else {
    Write-Host "`nNo metrics jobs found" -ForegroundColor Yellow
}

# Check module load state
Write-Host "`n=== Module Load State ===" -ForegroundColor Cyan
$module = Get-Module PSWebHost_Metrics
if ($module) {
    Write-Host "Module loaded: Yes" -ForegroundColor Green
    Write-Host "Path: $($module.Path)" -ForegroundColor Gray
    Write-Host "Version: $($module.Version)" -ForegroundColor Gray
} else {
    Write-Host "Module loaded: No" -ForegroundColor Yellow
}

Write-Host ""
