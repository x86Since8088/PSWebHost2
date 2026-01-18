<#
.SYNOPSIS
    Restarts the PSWebHost metrics collection job
.DESCRIPTION
    Stops any existing metrics collection job and starts a new one.
    This is useful when metrics collection has stopped and you don't want to restart the entire server.
.PARAMETER Force
    Force restart even if a job is currently running
.EXAMPLE
    .\Restart-MetricsCollection.ps1
    Starts metrics collection if not already running
.EXAMPLE
    .\Restart-MetricsCollection.ps1 -Force
    Stops existing job and starts a new one
#>

param(
    [switch]$Force
)

Write-Host "`n=== Metrics Collection Restart ===" -ForegroundColor Cyan

# Check current state
Write-Host "`nChecking current state..."
$existingJob = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue

if ($existingJob) {
    Write-Host "  Existing job found: State=$($existingJob.State)" -ForegroundColor Yellow

    if ($existingJob.State -eq 'Running' -and -not $Force) {
        Write-Host "  Metrics collection is already running" -ForegroundColor Green
        Write-Host "  Use -Force to restart the running job" -ForegroundColor Yellow

        # Check if actually collecting
        Write-Host "`nVerifying collection is working..."
        $recentFiles = Get-ChildItem -Path "PsWebHost_Data/metrics/*.csv" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 3

        if ($recentFiles) {
            Write-Host "  ✓ Recent CSV files found:" -ForegroundColor Green
            foreach ($file in $recentFiles) {
                $age = (Get-Date) - $file.LastWriteTime
                Write-Host "    - $($file.Name) ($([int]$age.TotalSeconds)s ago)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠ No recent CSV files found - job may be stalled" -ForegroundColor Yellow
            Write-Host "  Run with -Force to restart" -ForegroundColor Yellow
        }
        return
    }

    Write-Host "  Stopping existing job..."
    Stop-Job -Job $existingJob -ErrorAction SilentlyContinue
    Remove-Job -Job $existingJob -Force -ErrorAction SilentlyContinue

    # Also clear global reference
    if ($Global:PSWebServer.MetricsJob) {
        Remove-Variable -Name MetricsJob -Scope Global -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  ✓ Existing job stopped" -ForegroundColor Green
} else {
    Write-Host "  No existing job found" -ForegroundColor Gray
}

# Import module
Write-Host "`nInitializing metrics module..."
try {
    Import-Module PSWebHost_Metrics -Force -ErrorAction Stop
    Write-Host "  ✓ Module loaded" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to load module: $_" -ForegroundColor Red
    Write-Host "  Module path: $($Global:PSWebServer.Project_Root.Path)\modules\PSWebHost_Metrics" -ForegroundColor Gray
    return
}

# Initialize metrics storage
Write-Host "`nInitializing metrics storage..."
try {
    Initialize-PSWebMetrics -SampleIntervalSeconds 5 -RetentionHours 24 -CsvRetentionDays 30
    Write-Host "  ✓ Storage initialized" -ForegroundColor Green
    Write-Host "  Metrics directory: $($Global:PSWebServer.Metrics.Config.MetricsDirectory)" -ForegroundColor Gray
}
catch {
    Write-Host "  ✗ Failed to initialize: $_" -ForegroundColor Red
    return
}

# Reset job state
Write-Host "`nPreparing job state..."
if (-not $Global:PSWebServer.Metrics.JobState) {
    $Global:PSWebServer.Metrics.JobState = [hashtable]::Synchronized(@{
        ShouldStop = $false
        IsExecuting = $false
        Running = $true
        LastCollection = $null
        Errors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    })
} else {
    $Global:PSWebServer.Metrics.JobState.ShouldStop = $false
    $Global:PSWebServer.Metrics.JobState.IsExecuting = $false
    $Global:PSWebServer.Metrics.JobState.Running = $true
}
Write-Host "  ✓ Job state prepared" -ForegroundColor Green

# Start job
Write-Host "`nStarting metrics collection job..."
$modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules"

$Global:PSWebServer.MetricsJob = Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock {
    param($MetricsState, $ModulePath)

    # Import module in job context
    Import-Module (Join-Path $ModulePath "PSWebHost_Metrics") -Force -ErrorAction Stop

    while (-not $MetricsState.ShouldStop) {
        try {
            # Prevent concurrent execution
            if ($MetricsState.IsExecuting) {
                Start-Sleep -Milliseconds 500
                continue
            }

            $MetricsState.IsExecuting = $true

            # Collect metrics snapshot
            $snapshot = Get-SystemMetricsSnapshot -TimeoutSeconds 3

            if ($snapshot) {
                # Update in-memory storage and write to CSV
                Update-MetricsStorage -Snapshot $snapshot
                $MetricsState.LastCollection = Get-Date
            }

            $MetricsState.IsExecuting = $false
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Error "Metrics collection error: $_"
            if ($MetricsState.Errors.Count -lt 100) {
                $MetricsState.Errors.Add(@{
                    Timestamp = Get-Date
                    Error = $_.Exception.Message
                })
            }
            $MetricsState.IsExecuting = $false
            Start-Sleep -Seconds 5
        }
    }
} -ArgumentList $Global:PSWebServer.Metrics.JobState, $modulePath

# Verify job started
Start-Sleep -Seconds 2
$job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue

if ($job -and $job.State -eq 'Running') {
    Write-Host "  ✓ Job started successfully" -ForegroundColor Green
    Write-Host "    Job ID: $($job.Id)" -ForegroundColor Gray
    Write-Host "    State: $($job.State)" -ForegroundColor Gray
    Write-Host "    Location: Background PowerShell Job" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Job failed to start" -ForegroundColor Red
    if ($job) {
        Write-Host "    State: $($job.State)" -ForegroundColor Red

        # Try to get error output
        $jobErrors = Receive-Job -Job $job -ErrorAction SilentlyContinue
        if ($jobErrors) {
            Write-Host "    Errors:" -ForegroundColor Red
            $jobErrors | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
        }
    }
    return
}

# Wait a moment and check for errors
Write-Host "`nWaiting 5 seconds for first collection cycle..."
Start-Sleep -Seconds 5

$jobOutput = Receive-Job -Job $job -ErrorAction SilentlyContinue
if ($jobOutput) {
    Write-Host "  Job output:" -ForegroundColor Yellow
    $jobOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

# Check for new CSV files
Write-Host "`nVerifying CSV file creation..."
$veryRecentFiles = Get-ChildItem -Path "PsWebHost_Data/metrics/*.csv" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddSeconds(-10) } |
    Sort-Object LastWriteTime -Descending

if ($veryRecentFiles) {
    Write-Host "  ✓ New CSV files created:" -ForegroundColor Green
    foreach ($file in $veryRecentFiles | Select-Object -First 5) {
        $age = (Get-Date) - $file.LastWriteTime
        $sizeKB = [math]::Round($file.Length / 1KB, 1)
        Write-Host "    - $($file.Name) (${sizeKB}KB, $([int]$age.TotalSeconds)s ago)" -ForegroundColor Gray
    }
} else {
    Write-Host "  ⚠ No new CSV files detected yet" -ForegroundColor Yellow
    Write-Host "    This might be normal - wait 10 more seconds and check:" -ForegroundColor Gray
    Write-Host "    Get-ChildItem PsWebHost_Data/metrics/*.csv | Sort LastWriteTime -Desc | Select -First 5" -ForegroundColor Gray
}

# Summary
Write-Host "`n=== Restart Complete ===" -ForegroundColor Cyan
Write-Host "Metrics collection job is running" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 10-15 seconds for CSV files to be created" -ForegroundColor Gray
Write-Host "  2. Refresh the Server Load card in your browser (Ctrl+F5)" -ForegroundColor Gray
Write-Host "  3. Data should start appearing in the graph" -ForegroundColor Gray
Write-Host "`nTo monitor job status:" -ForegroundColor Yellow
Write-Host "  Get-Job -Name 'PSWebHost_MetricsCollection'" -ForegroundColor Gray
Write-Host "`nTo check recent files:" -ForegroundColor Yellow
Write-Host "  Get-ChildItem PsWebHost_Data/metrics/*.csv | Sort LastWriteTime -Desc | Select -First 5`n" -ForegroundColor Gray
