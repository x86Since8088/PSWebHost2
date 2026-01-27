# Test Metrics Collection - Run from server console
# This tests why metrics aren't being collected even though the job runs

Write-Host "`n=== Testing Metrics Collection Functions ===" -ForegroundColor Cyan

# Test 1: Can we collect a snapshot?
Write-Host "`n1. Testing Get-SystemMetricsSnapshot..." -ForegroundColor Yellow
try {
    $snapshot = Get-SystemMetricsSnapshot
    if ($snapshot) {
        Write-Host "   ✓ Snapshot collected successfully" -ForegroundColor Green
        Write-Host "   Timestamp: $($snapshot.Timestamp)" -ForegroundColor Gray
        Write-Host "   Hostname: $($snapshot.Hostname)" -ForegroundColor Gray
        Write-Host "   CPU Data: $($snapshot.Cpu.Keys -join ', ')" -ForegroundColor Gray
    } else {
        Write-Host "   ✗ Snapshot is null" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Can we update current metrics?
Write-Host "`n2. Testing Update-CurrentMetrics..." -ForegroundColor Yellow
try {
    if ($snapshot) {
        Update-CurrentMetrics -Snapshot $snapshot
        Write-Host "   ✓ Update-CurrentMetrics completed" -ForegroundColor Green
        Write-Host "   Current Timestamp: $($Global:PSWebServer.Metrics.Current.Timestamp)" -ForegroundColor Gray
    } else {
        Write-Host "   ✗ Cannot test - no snapshot available" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Can we add a sample?
Write-Host "`n3. Testing Add-MetricsSample..." -ForegroundColor Yellow
try {
    if ($snapshot) {
        $beforeCount = $Global:PSWebServer.Metrics.Samples.Count
        Add-MetricsSample -Snapshot $snapshot
        $afterCount = $Global:PSWebServer.Metrics.Samples.Count

        if ($afterCount -gt $beforeCount) {
            Write-Host "   ✓ Sample added successfully (count: $beforeCount → $afterCount)" -ForegroundColor Green
        } else {
            Write-Host "   ✗ Sample count didn't increase ($beforeCount → $afterCount)" -ForegroundColor Red
        }
    } else {
        Write-Host "   ✗ Cannot test - no snapshot available" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Can we write CSV?
Write-Host "`n4. Testing Write-MetricsToInterimCsv..." -ForegroundColor Yellow
try {
    # Collect 12 samples (1 minute worth at 5-second intervals)
    Write-Host "   Collecting 12 samples for CSV test..." -ForegroundColor Gray
    for ($i = 0; $i -lt 12; $i++) {
        $snap = Get-SystemMetricsSnapshot
        Add-MetricsSample -Snapshot $snap
        if ($i -lt 11) {
            Start-Sleep -Milliseconds 500  # Don't actually wait 5 seconds in test
        }
    }

    Write-Host "   Calling Write-MetricsToInterimCsv -Force..." -ForegroundColor Gray
    Write-MetricsToInterimCsv -Force

    # Check for new CSV files
    $csvFiles = Get-ChildItem 'PsWebHost_Data\metrics' -Filter '*_2026-*.csv' -ErrorAction SilentlyContinue |
        Where-Object { ((Get-Date) - $_.LastWriteTime).TotalSeconds -lt 10 }

    if ($csvFiles) {
        Write-Host "   ✓ CSV files created:" -ForegroundColor Green
        $csvFiles | ForEach-Object {
            Write-Host "     - $($_.Name)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   ✗ No new CSV files created" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
}

# Test 5: Test Invoke-MetricJobMaintenance directly
Write-Host "`n5. Testing Invoke-MetricJobMaintenance..." -ForegroundColor Yellow
try {
    $beforeSamples = $Global:PSWebServer.Metrics.Samples.Count
    $beforeTimestamp = $Global:PSWebServer.Metrics.Current.Timestamp

    Write-Host "   Before: Samples=$beforeSamples, Timestamp=$beforeTimestamp" -ForegroundColor Gray

    Invoke-MetricJobMaintenance

    $afterSamples = $Global:PSWebServer.Metrics.Samples.Count
    $afterTimestamp = $Global:PSWebServer.Metrics.Current.Timestamp

    Write-Host "   After: Samples=$afterSamples, Timestamp=$afterTimestamp" -ForegroundColor Gray

    if ($afterSamples -gt $beforeSamples) {
        Write-Host "   ✓ Invoke-MetricJobMaintenance is working!" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Invoke-MetricJobMaintenance didn't add samples" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Current State:" -ForegroundColor Yellow
Write-Host "  Sample Count: $($Global:PSWebServer.Metrics.Samples.Count)"
Write-Host "  Current Timestamp: $($Global:PSWebServer.Metrics.Current.Timestamp)"
Write-Host "  Last Collection: $($Global:PSWebServer.Metrics.JobState.LastCollection)"

Write-Host "`n=== End Test ===" -ForegroundColor Cyan
