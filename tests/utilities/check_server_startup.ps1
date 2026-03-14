# Check server startup and metrics initialization
Write-Host "Checking TestWebHost job output..." -ForegroundColor Cyan

$output = Receive-Job -Name 'TestWebHost' -Keep 2>&1

# Look for WebHostMetrics initialization
Write-Host "`n=== WebHostMetrics Initialization ===" -ForegroundColor Yellow
$metricsLines = $output | Where-Object { $_ -match 'WebHostMetrics|Metrics collection' }
if ($metricsLines) {
    $metricsLines | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "No WebHostMetrics output found" -ForegroundColor Red
}

# Look for errors
Write-Host "`n=== Errors/Warnings ===" -ForegroundColor Yellow
$errorLines = $output | Where-Object { $_ -match 'ERROR|WARNING.*Metrics' }
if ($errorLines) {
    $errorLines | Select-Object -Last 10 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
} else {
    Write-Host "No errors found" -ForegroundColor Green
}

# Check for the metrics job in the child jobs
Write-Host "`n=== Looking for Metrics Job ===" -ForegroundColor Yellow
$job = Get-Job -Name 'TestWebHost'
if ($job.ChildJobs[0]) {
    $childJob = $job.ChildJobs[0]

    # Try to access the global variable from the job (won't work, but let's check state)
    Write-Host "Child Job State: $($childJob.State)" -ForegroundColor Cyan
    Write-Host "Child Job HasMoreData: $($childJob.HasMoreData)" -ForegroundColor Cyan
}

Write-Host "`n=== Waiting 10 seconds for metrics job to start ===" -ForegroundColor Cyan
Start-Sleep -Seconds 10

# Check for new CSV files
Write-Host "`n=== Checking for CSV Files ===" -ForegroundColor Yellow
$csvFiles = Get-ChildItem 'PsWebHost_Data\metrics' -Filter '*_20*.csv' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 5

if ($csvFiles) {
    foreach ($file in $csvFiles) {
        $age = ((Get-Date) - $file.LastWriteTime).TotalMinutes
        if ($age -lt 1) {
            Write-Host "✓ $($file.Name) - $(([int]($age * 60)))s ago" -ForegroundColor Green
        } else {
            Write-Host "  $($file.Name) - $([int]$age)m ago" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "No CSV files found" -ForegroundColor Red
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
