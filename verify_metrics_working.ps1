# Verify Metrics Collection is Working
# Run this from the PSWebHost server console

Write-Host "`n=== Metrics Collection Verification ===" -ForegroundColor Cyan

# 1. Check if job exists and is running
Write-Host "`n1. Job Status:" -ForegroundColor Yellow
$job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue
if ($job) {
    Write-Host "   Job ID: $($job.Id)" -ForegroundColor Green
    Write-Host "   Job State: $($job.State)" -ForegroundColor Green
    Write-Host "   Has Data: $($job.HasMoreData)" -ForegroundColor Green
} else {
    Write-Host "   ERROR: Job not found!" -ForegroundColor Red
    exit
}

# 2. Get job output
Write-Host "`n2. Job Output (last 30 lines):" -ForegroundColor Yellow
$output = Receive-Job -Job $job -Keep 2>&1
if ($output) {
    $output | Select-Object -Last 30 | ForEach-Object {
        if ($_ -match 'ERROR|Exception') {
            Write-Host "   $_" -ForegroundColor Red
        } elseif ($_ -match 'WARNING') {
            Write-Host "   $_" -ForegroundColor Yellow
        } elseif ($_ -match 'Iteration|Executing|completed') {
            Write-Host "   $_" -ForegroundColor Cyan
        } else {
            Write-Host "   $_" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   (No output yet - job may still be starting)" -ForegroundColor Yellow
}

# 3. Check metrics object
Write-Host "`n3. Metrics Object Status:" -ForegroundColor Yellow
if ($Global:PSWebServer.Metrics) {
    Write-Host "   Current Timestamp: $($Global:PSWebServer.Metrics.Current.Timestamp)" -ForegroundColor Green
    Write-Host "   Sample Count: $($Global:PSWebServer.Metrics.Samples.Count)" -ForegroundColor Green
    Write-Host "   Last Collection: $($Global:PSWebServer.Metrics.JobState.LastCollection)" -ForegroundColor Green
    Write-Host "   Last CSV Write: $($Global:PSWebServer.Metrics.JobState.LastInterimCsvWrite)" -ForegroundColor Green
} else {
    Write-Host "   ERROR: Metrics object not found!" -ForegroundColor Red
}

# 4. Check for new CSV files
Write-Host "`n4. CSV Files:" -ForegroundColor Yellow
$csvDir = "PsWebHost_Data\metrics"
if (Test-Path $csvDir) {
    $recentFiles = Get-ChildItem $csvDir |
        Where-Object { $_.Name -match '^\w+_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.csv$' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10

    if ($recentFiles) {
        $now = Get-Date
        Write-Host "   Most recent CSV files:" -ForegroundColor Cyan

        foreach ($file in $recentFiles) {
            $age = ($now - $file.LastWriteTime).TotalMinutes
            $ageStr = if ($age -lt 1) {
                "$([int]($age * 60))s ago"
            } elseif ($age -lt 60) {
                "$([int]$age)m ago"
            } else {
                "$([int]($age/60))h ago"
            }

            $color = if ($age -lt 2) { 'Green' } elseif ($age -lt 60) { 'Yellow' } else { 'Gray' }
            Write-Host "   $($file.Name) - $ageStr" -ForegroundColor $color
        }

        # Check if collection is working (file less than 2 minutes old)
        $newest = $recentFiles[0]
        $ageMinutes = ($now - $newest.LastWriteTime).TotalMinutes

        Write-Host ""
        if ($ageMinutes -lt 2) {
            Write-Host "   ✓ SUCCESS: Metrics collection is WORKING! (newest file is $([int]($ageMinutes * 60)) seconds old)" -ForegroundColor Green
        } elseif ($ageMinutes -lt 10) {
            Write-Host "   ⚠ WARNING: Latest file is $([int]$ageMinutes) minutes old - may be delayed" -ForegroundColor Yellow
        } else {
            Write-Host "   ✗ FAIL: Latest file is $([int]$ageMinutes) minutes old - collection appears stopped" -ForegroundColor Red
        }
    } else {
        Write-Host "   No CSV files with expected naming pattern found" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ERROR: CSV directory not found: $csvDir" -ForegroundColor Red
}

# 5. Check for errors
Write-Host "`n5. Error Check:" -ForegroundColor Yellow
if ($Global:PSWebServer.Metrics.JobState.Errors.Count -gt 0) {
    Write-Host "   Found $($Global:PSWebServer.Metrics.JobState.Errors.Count) errors:" -ForegroundColor Red
    $Global:PSWebServer.Metrics.JobState.Errors | Select-Object -Last 3 | ForEach-Object {
        Write-Host "   [$($_.Timestamp)] $($_.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "   ✓ No errors logged" -ForegroundColor Green
}

# 6. Test current metrics API
Write-Host "`n6. Testing Current Metrics API:" -ForegroundColor Yellow
try {
    $currentMetrics = Get-CurrentMetrics
    if ($currentMetrics) {
        Write-Host "   ✓ Get-CurrentMetrics returned data" -ForegroundColor Green
        Write-Host "   CPU Avg: $($currentMetrics.cpu.AvgPercent)%" -ForegroundColor Cyan
        Write-Host "   Memory Used: $($currentMetrics.memory.PercentUsed)%" -ForegroundColor Cyan
    } else {
        Write-Host "   ⚠ Get-CurrentMetrics returned null" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ✗ Error calling Get-CurrentMetrics: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Verification Complete ===" -ForegroundColor Cyan
Write-Host ""
