# Metrics Collection Diagnostic Script
# Run this from within the PSWebHost server session

Write-Host "=== Metrics Collection Diagnostic ===" -ForegroundColor Cyan

# Check if WebHostMetrics app is loaded
Write-Host "`n1. Checking WebHostMetrics app status..." -ForegroundColor Yellow
if ($Global:PSWebServer.WebHostMetrics) {
    Write-Host "   WebHostMetrics app is loaded" -ForegroundColor Green
    $Global:PSWebServer.WebHostMetrics | Format-List
} else {
    Write-Host "   WebHostMetrics app is NOT loaded" -ForegroundColor Red
}

# Check if Metrics object exists
Write-Host "`n2. Checking Metrics object..." -ForegroundColor Yellow
if ($Global:PSWebServer.Metrics) {
    Write-Host "   Metrics object exists" -ForegroundColor Green
    Write-Host "   Current timestamp: $($Global:PSWebServer.Metrics.Current.Timestamp)"
    Write-Host "   Sample count: $($Global:PSWebServer.Metrics.Samples.Count)"
    Write-Host "   Last collection: $($Global:PSWebServer.Metrics.JobState.LastCollection)"
} else {
    Write-Host "   Metrics object does NOT exist" -ForegroundColor Red
}

# Check if job is running
Write-Host "`n3. Checking metrics collection job..." -ForegroundColor Yellow
if ($Global:PSWebServer.MetricsJob) {
    Write-Host "   Job exists" -ForegroundColor Green
    $Global:PSWebServer.MetricsJob | Format-List Id, Name, State, HasMoreData

    Write-Host "`n   Job output (last 20 lines):" -ForegroundColor Cyan
    Receive-Job -Job $Global:PSWebServer.MetricsJob -Keep 2>&1 | Select-Object -Last 20 | ForEach-Object {
        if ($_ -match 'Error|WARNING') {
            Write-Host "   $_" -ForegroundColor Red
        } else {
            Write-Host "   $_"
        }
    }
} else {
    Write-Host "   Job does NOT exist" -ForegroundColor Red

    # Check all jobs
    Write-Host "`n   All running jobs:" -ForegroundColor Cyan
    Get-Job | Format-Table Id, Name, State -AutoSize
}

# Check for errors
Write-Host "`n4. Checking for errors..." -ForegroundColor Yellow
if ($Global:PSWebServer.Metrics.JobState.Errors.Count -gt 0) {
    Write-Host "   Found $($Global:PSWebServer.Metrics.JobState.Errors.Count) errors" -ForegroundColor Red
    $Global:PSWebServer.Metrics.JobState.Errors | Select-Object -Last 5 | ForEach-Object {
        Write-Host "   [$($_.Timestamp)] $($_.Message)" -ForegroundColor Red
        if ($_.StackTrace) {
            Write-Host "   $($_.StackTrace)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   No errors logged" -ForegroundColor Green
}

# Check CSV files
Write-Host "`n5. Checking CSV files..." -ForegroundColor Yellow
$csvDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\metrics"
if (Test-Path $csvDir) {
    $recentFiles = Get-ChildItem $csvDir | Sort-Object LastWriteTime -Descending | Select-Object -First 5
    if ($recentFiles) {
        Write-Host "   Most recent CSV files:" -ForegroundColor Cyan
        $recentFiles | Format-Table Name, LastWriteTime, @{Name='Size';Expression={$_.Length}} -AutoSize

        $newestFile = $recentFiles[0]
        $ageMinutes = ((Get-Date) - $newestFile.LastWriteTime).TotalMinutes
        if ($ageMinutes -lt 5) {
            Write-Host "   Latest file is recent (${ageMinutes} minutes old) - collection is working!" -ForegroundColor Green
        } else {
            Write-Host "   Latest file is old (${ageMinutes} minutes old) - collection may not be working" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   No CSV files found" -ForegroundColor Red
    }
} else {
    Write-Host "   CSV directory does not exist: $csvDir" -ForegroundColor Red
}

# Check module
Write-Host "`n6. Checking PSWebHost_Metrics module..." -ForegroundColor Yellow
$module = Get-Module PSWebHost_Metrics
if ($module) {
    Write-Host "   Module is loaded" -ForegroundColor Green
    Write-Host "   Path: $($module.Path)"
    Write-Host "   Version: $($module.Version)"
} else {
    Write-Host "   Module is NOT loaded" -ForegroundColor Red

    # Try to find it
    $modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "apps\WebHostMetrics\modules\PSWebHost_Metrics\PSWebHost_Metrics.psm1"
    if (Test-Path $modulePath) {
        Write-Host "   Module file exists at: $modulePath" -ForegroundColor Yellow
    } else {
        Write-Host "   Module file NOT found at: $modulePath" -ForegroundColor Red
    }
}

Write-Host "`n=== End Diagnostic ===" -ForegroundColor Cyan
