# Quick Metrics Check - Run from server console
Write-Host "`n=== Quick Metrics Check ===" -ForegroundColor Cyan

# 1. Check if metrics job exists
Write-Host "`n1. Metrics Job:" -ForegroundColor Yellow
$job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue
if ($job) {
    Write-Host "   ✓ Job exists: $($job.Name) (ID: $($job.Id), State: $($job.State))" -ForegroundColor Green

    # Get job output
    Write-Host "`n2. Job Output (last 30 lines):" -ForegroundColor Yellow
    $output = Receive-Job -Job $job -Keep 2>&1
    if ($output) {
        $output | Select-Object -Last 30 | ForEach-Object {
            if ($_ -match '\[MetricsJob\]') {
                Write-Host "   $_" -ForegroundColor Cyan
            } elseif ($_ -match 'error|exception') {
                Write-Host "   $_" -ForegroundColor Red
            } else {
                Write-Host "   $_" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "   (No output - job may not be executing)" -ForegroundColor Red
    }
} else {
    Write-Host "   ✗ Job NOT found" -ForegroundColor Red
}

# 2. Check metrics object
Write-Host "`n3. Metrics Object:" -ForegroundColor Yellow
if ($Global:PSWebServer.Metrics) {
    Write-Host "   ✓ Metrics object exists" -ForegroundColor Green
    Write-Host "   Current Timestamp: $($Global:PSWebServer.Metrics.Current.Timestamp)"
    Write-Host "   Sample Count: $($Global:PSWebServer.Metrics.Samples.Count)"
    Write-Host "   Last Collection: $($Global:PSWebServer.Metrics.JobState.LastCollection)"
} else {
    Write-Host "   ✗ Metrics object NOT found" -ForegroundColor Red
}

# 3. Check CSV files
Write-Host "`n4. Recent CSV Files:" -ForegroundColor Yellow
$csvFiles = Get-ChildItem 'PsWebHost_Data\metrics' -Filter '*_2026-*.csv' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 5

if ($csvFiles) {
    $now = Get-Date
    foreach ($file in $csvFiles) {
        $age = ($now - $file.LastWriteTime).TotalSeconds
        if ($age -lt 120) {
            Write-Host "   ✓ $($file.Name) - $([int]$age)s ago" -ForegroundColor Green
        } else {
            $ageMin = [int](($now - $file.LastWriteTime).TotalMinutes)
            Write-Host "   ✗ $($file.Name) - ${ageMin}m ago" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   (No recent CSV files)" -ForegroundColor Red
}

# 4. Check server port
Write-Host "`n5. Server Port:" -ForegroundColor Yellow
if ($Global:PSWebServer.Listener) {
    Write-Host "   ✓ Server listening on: http://localhost:$($Global:PSWebServer.Listener.Prefixes)" -ForegroundColor Green
} else {
    Write-Host "   ? Cannot determine port" -ForegroundColor Yellow
}

Write-Host "`n=== End Check ===" -ForegroundColor Cyan
