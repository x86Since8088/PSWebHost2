# Test Metrics Fix - Verify module scope issue is resolved
# Run this from the server console after starting WebHost.ps1

Write-Host "`n=== Testing Metrics Collection Fix ===" -ForegroundColor Cyan
Write-Host "This tests the module scope fix where MetricsDirectory was NULL in job scope`n" -ForegroundColor Gray

# Test 1: Check that MetricsDirectory is set in the synchronized Config
Write-Host "1. Checking Config.MetricsDirectory in parent scope..." -ForegroundColor Yellow
if ($Global:PSWebServer.Metrics.Config.MetricsDirectory) {
    Write-Host "   ✓ MetricsDirectory is set: $($Global:PSWebServer.Metrics.Config.MetricsDirectory)" -ForegroundColor Green
} else {
    Write-Host "   ✗ MetricsDirectory is NULL - this is a problem!" -ForegroundColor Red
    Write-Host "   Run Initialize-PSWebMetrics to fix this" -ForegroundColor Yellow
    exit 1
}

# Test 2: Wait for job to collect at least one sample
Write-Host "`n2. Waiting for job to collect samples (15 seconds)..." -ForegroundColor Yellow
$startCount = $Global:PSWebServer.Metrics.Samples.Count
Write-Host "   Starting sample count: $startCount" -ForegroundColor Gray

Start-Sleep -Seconds 15

$endCount = $Global:PSWebServer.Metrics.Samples.Count
Write-Host "   Ending sample count: $endCount" -ForegroundColor Gray

if ($endCount -gt $startCount) {
    Write-Host "   ✓ Samples are being collected! ($startCount → $endCount)" -ForegroundColor Green
} else {
    Write-Host "   ✗ No samples collected - job may still have issues" -ForegroundColor Red
}

# Test 3: Check if Current timestamp is being updated
Write-Host "`n3. Checking Current.Timestamp..." -ForegroundColor Yellow
$currentTimestamp = $Global:PSWebServer.Metrics.Current.Timestamp
if ($currentTimestamp) {
    $age = ((Get-Date) - [datetime]::Parse($currentTimestamp)).TotalSeconds
    Write-Host "   ✓ Current timestamp: $currentTimestamp (${age}s ago)" -ForegroundColor Green
} else {
    Write-Host "   ✗ Current timestamp is empty" -ForegroundColor Red
}

# Test 4: Check LastCollection timestamp
Write-Host "`n4. Checking LastCollection..." -ForegroundColor Yellow
$lastCollection = $Global:PSWebServer.Metrics.JobState.LastCollection
if ($lastCollection) {
    $age = ((Get-Date) - $lastCollection).TotalSeconds
    Write-Host "   ✓ LastCollection: $lastCollection (${age}s ago)" -ForegroundColor Green
} else {
    Write-Host "   ✗ LastCollection is empty" -ForegroundColor Red
}

# Test 5: Force CSV write and check for files
Write-Host "`n5. Testing CSV file creation..." -ForegroundColor Yellow
Write-Host "   Collecting 12 samples..." -ForegroundColor Gray

# Manually trigger metrics collection for testing
for ($i = 0; $i -lt 12; $i++) {
    try {
        $snapshot = Get-SystemMetricsSnapshot
        Update-CurrentMetrics -Snapshot $snapshot
        Add-MetricsSample -Snapshot $snapshot
    } catch {
        Write-Host "   Error collecting sample: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "   Forcing CSV write..." -ForegroundColor Gray
try {
    Write-MetricsToInterimCsv -Force
    Write-Host "   ✓ Write-MetricsToInterimCsv completed" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Write-MetricsToInterimCsv failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Check for new CSV files
$metricsDir = $Global:PSWebServer.Metrics.Config.MetricsDirectory
Write-Host "   Checking $metricsDir for new files..." -ForegroundColor Gray

$csvFiles = Get-ChildItem $metricsDir -Filter '*_2026-*.csv' -ErrorAction SilentlyContinue |
    Where-Object { ((Get-Date) - $_.LastWriteTime).TotalSeconds -lt 30 } |
    Sort-Object LastWriteTime -Descending

if ($csvFiles) {
    Write-Host "   ✓ CSV files created:" -ForegroundColor Green
    $csvFiles | ForEach-Object {
        $age = [int]((Get-Date) - $_.LastWriteTime).TotalSeconds
        Write-Host "     - $($_.Name) (${age}s ago, $($_.Length) bytes)" -ForegroundColor Gray
    }
} else {
    Write-Host "   ✗ No new CSV files created" -ForegroundColor Red
    Write-Host "   Check if MetricsDirectory exists and is writable" -ForegroundColor Yellow
}

# Test 6: Check job output for errors
Write-Host "`n6. Checking job for errors..." -ForegroundColor Yellow
$job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue
if ($job) {
    $jobErrors = $job.ChildJobs[0].Error
    if ($jobErrors.Count -gt 0) {
        Write-Host "   ✗ Job has $($jobErrors.Count) errors:" -ForegroundColor Red
        $jobErrors | Select-Object -Last 3 | ForEach-Object {
            Write-Host "     - $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "   ✓ No job errors" -ForegroundColor Green
    }

    # Check JobState errors
    $stateErrors = $Global:PSWebServer.Metrics.JobState.Errors
    if ($stateErrors.Count -gt 0) {
        Write-Host "   ✗ JobState has $($stateErrors.Count) errors:" -ForegroundColor Red
        $stateErrors | Select-Object -Last 3 | ForEach-Object {
            Write-Host "     - $($_.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "   ✓ No JobState errors" -ForegroundColor Green
    }
} else {
    Write-Host "   ✗ Job not found!" -ForegroundColor Red
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Metrics System State:" -ForegroundColor Yellow
Write-Host "  Config.MetricsDirectory: $($Global:PSWebServer.Metrics.Config.MetricsDirectory)"
Write-Host "  Sample Count: $($Global:PSWebServer.Metrics.Samples.Count)"
Write-Host "  Current Timestamp: $($Global:PSWebServer.Metrics.Current.Timestamp)"
Write-Host "  LastCollection: $($Global:PSWebServer.Metrics.JobState.LastCollection)"
Write-Host "  LastInterimCsvWrite: $($Global:PSWebServer.Metrics.JobState.LastInterimCsvWrite)"
Write-Host "  Job State: $($job.State)" -ForegroundColor $(if ($job.State -eq 'Running') { 'Green' } else { 'Red' })

Write-Host "`nIf samples are being collected and CSV files are created, the fix is working!" -ForegroundColor Cyan
Write-Host "=== End Test ===`n" -ForegroundColor Cyan
