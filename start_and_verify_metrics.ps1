# Start WebHost and Verify Metrics Collection
# This script must be run from a PowerShell console (not bash)

Write-Host "`n=== Starting PSWebHost Server ===" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop the server when done testing`n" -ForegroundColor Yellow

# Start the server in the background
$serverJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    .\WebHost.ps1 -Port 8080
}

Write-Host "Server job started (ID: $($serverJob.Id))" -ForegroundColor Green
Write-Host "Waiting 20 seconds for server to initialize..." -ForegroundColor Cyan
Start-Sleep -Seconds 20

Write-Host "`n=== Checking Server Output ===" -ForegroundColor Yellow
$output = Receive-Job -Job $serverJob -Keep 2>&1

# Show WebHostMetrics initialization
$metricsOutput = $output | Where-Object { $_ -match 'WebHostMetrics' }
if ($metricsOutput) {
    Write-Host "WebHostMetrics initialization:" -ForegroundColor Green
    $metricsOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
} else {
    Write-Host "WARNING: No WebHostMetrics output found!" -ForegroundColor Red
}

# Check for errors
$errors = $output | Where-Object { $_ -match 'ERROR|Failed.*Metrics|WARNING.*Metrics' }
if ($errors) {
    Write-Host "`nErrors/Warnings found:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

# Wait for metrics job to start and run
Write-Host "`nWaiting 65 seconds for metrics to collect (1 minute for CSV generation)..." -ForegroundColor Cyan
Start-Sleep -Seconds 65

# Check for new CSV files
Write-Host "`n=== Checking CSV Files ===" -ForegroundColor Yellow
$now = Get-Date
$csvFiles = Get-ChildItem 'PsWebHost_Data\metrics' -Filter '*_2026-*.csv' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10

if ($csvFiles) {
    $foundNew = $false
    foreach ($file in $csvFiles) {
        $age = ($now - $file.LastWriteTime).TotalSeconds
        if ($age -lt 120) {  # Less than 2 minutes old
            Write-Host "✓ NEW: $($file.Name) - $([int]$age)s ago" -ForegroundColor Green
            $foundNew = $true
        } else {
            $ageMin = [int](($now - $file.LastWriteTime).TotalMinutes)
            Write-Host "  OLD: $($file.Name) - ${ageMin}m ago" -ForegroundColor Gray
        }
    }

    if ($foundNew) {
        Write-Host "`n✓✓✓ SUCCESS! Metrics collection is working! ✓✓✓" -ForegroundColor Green
    } else {
        Write-Host "`n✗ FAILED: No new CSV files created in the last 2 minutes" -ForegroundColor Red
        Write-Host "The metrics job may not be running or has errors" -ForegroundColor Yellow
    }
} else {
    Write-Host "No CSV files found in PsWebHost_Data\metrics" -ForegroundColor Red
}

# Show job status
Write-Host "`n=== Server Job Status ===" -ForegroundColor Yellow
Get-Job -Id $serverJob.Id | Format-List Id, Name, State, HasMoreData

Write-Host "`nTo stop the server:" -ForegroundColor Cyan
Write-Host "  Stop-Job -Id $($serverJob.Id); Remove-Job -Id $($serverJob.Id)" -ForegroundColor White

Write-Host "`nTo see server logs:" -ForegroundColor Cyan
Write-Host "  Receive-Job -Id $($serverJob.Id) -Keep" -ForegroundColor White

Write-Host "`n=== Verification Complete ===" -ForegroundColor Cyan
