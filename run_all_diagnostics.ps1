# Run All Diagnostics - Complete server health check
# Run this from the server console (no authentication needed)

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PSWebHost Complete Diagnostic Suite         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$allPassed = $true

# Test 1: Runspace Pool Status
Write-Host "━━━ Test 1: Runspace Pool Status ━━━" -ForegroundColor Yellow
try {
    $poolStatus = @{
        Initialized = $AsyncRunspacePool.Initialized
        WorkerCount = $AsyncRunspacePool.Workers.Count
        StopRequested = $AsyncRunspacePool.StopRequested
        HasListener = $null -ne $AsyncRunspacePool.ListenerInstance
        ListenerIsListening = if ($AsyncRunspacePool.ListenerInstance) { $AsyncRunspacePool.ListenerInstance.IsListening } else { $false }
    }

    Write-Host "  Initialized: $($poolStatus.Initialized)" -ForegroundColor $(if ($poolStatus.Initialized) { 'Green' } else { 'Red' })
    Write-Host "  Workers: $($poolStatus.WorkerCount)" -ForegroundColor $(if ($poolStatus.WorkerCount -eq 15) { 'Green' } else { 'Yellow' })
    Write-Host "  Listener Active: $($poolStatus.ListenerIsListening)" -ForegroundColor $(if ($poolStatus.ListenerIsListening) { 'Green' } else { 'Red' })

    if (-not $poolStatus.Initialized -or -not $poolStatus.ListenerIsListening) {
        $allPassed = $false
        Write-Host "  ✗ FAIL: Runspace pool not properly initialized" -ForegroundColor Red
    } else {
        Write-Host "  ✓ PASS" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}

# Test 2: Worker States
Write-Host "`n━━━ Test 2: Worker Activity ━━━" -ForegroundColor Yellow
try {
    $workers = $AsyncRunspacePool.Stats.Values | ForEach-Object {
        [PSCustomObject]@{
            State = $_.State
            RequestCount = $_.RequestCount
            Errors = $_.Errors
        }
    }

    $stateGroups = $workers | Group-Object State
    $stateGroups | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) workers" -ForegroundColor Gray
    }

    $totalRequests = ($workers | Measure-Object RequestCount -Sum).Sum
    $totalErrors = ($workers | Measure-Object Errors -Sum).Sum

    Write-Host "  Total Requests Processed: $totalRequests" -ForegroundColor $(if ($totalRequests -gt 0) { 'Green' } else { 'Yellow' })
    Write-Host "  Total Errors: $totalErrors" -ForegroundColor $(if ($totalErrors -eq 0) { 'Green' } else { 'Red' })

    if ($totalRequests -eq 0) {
        Write-Host "  ⚠️  WARNING: No requests processed yet" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ PASS: Workers are processing requests" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}

# Test 3: Metrics Collection
Write-Host "`n━━━ Test 3: Metrics Collection ━━━" -ForegroundColor Yellow
try {
    $metricsStatus = @{
        Initialized = $null -ne $Global:PSWebServer.Metrics
        ConfigDir = $Global:PSWebServer.Metrics.Config.MetricsDirectory
        SampleCount = $Global:PSWebServer.Metrics.Samples.Count
        CurrentTimestamp = $Global:PSWebServer.Metrics.Current.Timestamp
        LastCollection = $Global:PSWebServer.Metrics.JobState.LastCollection
    }

    Write-Host "  Config Directory: $($metricsStatus.ConfigDir)" -ForegroundColor Gray
    Write-Host "  Sample Count: $($metricsStatus.SampleCount)" -ForegroundColor $(if ($metricsStatus.SampleCount -gt 0) { 'Green' } else { 'Red' })
    Write-Host "  Current Timestamp: $($metricsStatus.CurrentTimestamp)" -ForegroundColor $(if ($metricsStatus.CurrentTimestamp) { 'Green' } else { 'Red' })

    if ($metricsStatus.LastCollection) {
        $age = ((Get-Date) - $metricsStatus.LastCollection).TotalSeconds
        Write-Host "  Last Collection: $([int]$age)s ago" -ForegroundColor $(if ($age -lt 30) { 'Green' } else { 'Yellow' })
    } else {
        Write-Host "  Last Collection: Never" -ForegroundColor Red
    }

    # Check for CSV files
    if ($metricsStatus.ConfigDir -and (Test-Path $metricsStatus.ConfigDir)) {
        $recentCsvs = Get-ChildItem $metricsStatus.ConfigDir -Filter '*_2026-*.csv' -ErrorAction SilentlyContinue |
            Where-Object { ((Get-Date) - $_.LastWriteTime).TotalMinutes -lt 5 } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 3

        if ($recentCsvs) {
            Write-Host "  Recent CSV Files:" -ForegroundColor Green
            $recentCsvs | ForEach-Object {
                $age = [int]((Get-Date) - $_.LastWriteTime).TotalSeconds
                Write-Host "    - $($_.Name) (${age}s ago)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠️  No recent CSV files (last 5 minutes)" -ForegroundColor Yellow
        }
    }

    if ($metricsStatus.SampleCount -gt 0 -and $metricsStatus.CurrentTimestamp) {
        Write-Host "  ✓ PASS: Metrics collection is working" -ForegroundColor Green
    } else {
        Write-Host "  ✗ FAIL: Metrics not being collected" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "  ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}

# Test 4: Metrics Job Status
Write-Host "`n━━━ Test 4: Metrics Job ━━━" -ForegroundColor Yellow
try {
    $job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue
    if ($job) {
        Write-Host "  Job ID: $($job.Id)" -ForegroundColor Gray
        Write-Host "  State: $($job.State)" -ForegroundColor $(if ($job.State -eq 'Running') { 'Green' } else { 'Red' })

        # Check for errors
        $jobErrors = @($job.ChildJobs[0].Error)
        $stateErrors = @($Global:PSWebServer.Metrics.JobState.Errors)

        Write-Host "  Job Errors: $($jobErrors.Count)" -ForegroundColor $(if ($jobErrors.Count -eq 0) { 'Green' } else { 'Red' })
        Write-Host "  State Errors: $($stateErrors.Count)" -ForegroundColor $(if ($stateErrors.Count -eq 0) { 'Green' } else { 'Red' })

        if ($jobErrors.Count -gt 0) {
            Write-Host "  Recent Job Errors:" -ForegroundColor Red
            $jobErrors | Select-Object -Last 3 | ForEach-Object {
                Write-Host "    - $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        if ($job.State -eq 'Running') {
            Write-Host "  ✓ PASS: Job is running" -ForegroundColor Green
        } else {
            Write-Host "  ✗ FAIL: Job is not running" -ForegroundColor Red
            $allPassed = $false
        }
    } else {
        Write-Host "  ✗ FAIL: Metrics job not found" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "  ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}

# Test 5: Make a Test Request
Write-Host "`n━━━ Test 5: Test HTTP Request ━━━" -ForegroundColor Yellow
try {
    # Determine port from listener
    $port = if ($PSWebServer.Port) {
        $PSWebServer.Port
    } elseif ($PSWebServer.Listener -and $PSWebServer.Listener.Prefixes) {
        # Extract port from listener prefix (e.g., "http://+:8080/")
        $prefix = $PSWebServer.Listener.Prefixes | Select-Object -First 1
        if ($prefix -match ':(\d+)/') {
            $matches[1]
        } else {
            8080  # Default
        }
    } else {
        8080  # Default fallback
    }

    Write-Host "  Making request to http://localhost:$port/api/v1/metrics..." -ForegroundColor Gray

    $beforeRequests = ($AsyncRunspacePool.Stats.Values | Measure-Object RequestCount -Sum).Sum

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri "http://localhost:$port/api/v1/metrics" -TimeoutSec 5 -UseBasicParsing
    $sw.Stop()

    $afterRequests = ($AsyncRunspacePool.Stats.Values | Measure-Object RequestCount -Sum).Sum

    Write-Host "  Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "  Response Time: $($sw.ElapsedMilliseconds)ms" -ForegroundColor Gray
    Write-Host "  Requests Before: $beforeRequests, After: $afterRequests" -ForegroundColor Gray

    if ($afterRequests -gt $beforeRequests) {
        Write-Host "  ✓ PASS: Request was processed by a worker!" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  WARNING: Request succeeded but worker count didn't increment" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ✗ FAIL: Request failed - $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}

# Test 6: Check Logs for Recent Activity
Write-Host "`n━━━ Test 6: Recent Log Activity ━━━" -ForegroundColor Yellow
try {
    if ($Global:PSWebHostLogQueue) {
        $queueCount = $Global:PSWebHostLogQueue.Count
        Write-Host "  Queue Count: $queueCount" -ForegroundColor Gray

        if ($queueCount -eq 0) {
            Write-Host "  ℹ️  Log queue is empty (this is normal if logging to file)" -ForegroundColor Cyan
            Write-Host "  ✓ PASS: Logging system is available" -ForegroundColor Green
        } else {
            # Sample recent log entries (non-destructive peek)
            $sampleSize = [Math]::Min(100, $queueCount)
            $recentLogs = @()

            # Create a copy of the queue to sample
            $tempArray = $Global:PSWebHostLogQueue.ToArray()
            $recentLogs = $tempArray | Select-Object -Last $sampleSize

            $asyncWorkerLogs = @($recentLogs | Where-Object { $_ -match 'AsyncWorker' })
            $metricsLogs = @($recentLogs | Where-Object { $_ -match 'MetricsJob|Metrics\]' })

            Write-Host "  Total Log Entries Sampled: $($recentLogs.Count)" -ForegroundColor Gray
            Write-Host "  AsyncWorker Entries: $($asyncWorkerLogs.Count)" -ForegroundColor Gray
            Write-Host "  Metrics Entries: $($metricsLogs.Count)" -ForegroundColor Gray

            # Show most recent async worker log
            if ($asyncWorkerLogs.Count -gt 0) {
                $latest = $asyncWorkerLogs[-1] -split "`t"
                if ($latest.Count -ge 5) {
                    Write-Host "  Latest AsyncWorker: $($latest[4])" -ForegroundColor Cyan
                }
            }

            # Show most recent metrics log
            if ($metricsLogs.Count -gt 0) {
                $latest = $metricsLogs[-1] -split "`t"
                if ($latest.Count -ge 5) {
                    Write-Host "  Latest Metrics: $($latest[4])" -ForegroundColor Cyan
                }
            }

            Write-Host "  ✓ PASS: Logging system is active" -ForegroundColor Green
        }
    } else {
        Write-Host "  ⚠️  WARNING: Log queue not available" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Final Summary
Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║            DIAGNOSTIC SUMMARY                  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($allPassed) {
    Write-Host "`n  ✓ ALL CRITICAL TESTS PASSED" -ForegroundColor Green
    Write-Host "  Server appears to be functioning correctly." -ForegroundColor Green
} else {
    Write-Host "`n  ✗ SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "  Review the failures above for details." -ForegroundColor Yellow
}

Write-Host "`n  For detailed diagnostics, run:" -ForegroundColor Yellow
Write-Host "    . .\diagnose_runspace_deadlock.ps1" -ForegroundColor Cyan
Write-Host "    . .\test_metrics_fix.ps1" -ForegroundColor Cyan
Write-Host "`n"
