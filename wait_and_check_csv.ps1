Write-Host "Waiting 70 seconds for metrics collection..." -ForegroundColor Cyan
Start-Sleep -Seconds 70

Write-Host "`nChecking for new CSV files..." -ForegroundColor Yellow
$now = Get-Date
$csvFiles = Get-ChildItem 'PsWebHost_Data\metrics' -Filter '*_2026-*.csv' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10

if ($csvFiles) {
    $foundNew = $false
    foreach ($file in $csvFiles) {
        $age = ($now - $file.LastWriteTime).TotalSeconds
        if ($age -lt 120) {
            Write-Host "✓ NEW: $($file.Name) - $([int]$age)s ago" -ForegroundColor Green
            $foundNew = $true
        } else {
            $ageMin = [int](($now - $file.LastWriteTime).TotalMinutes)
            Write-Host "  OLD: $($file.Name) - ${ageMin}m ago" -ForegroundColor Gray
        }
    }

    if ($foundNew) {
        Write-Host "`n✓✓✓ SUCCESS! Metrics collection is WORKING! ✓✓✓" -ForegroundColor Green
    } else {
        Write-Host "`n✗ FAIL: No new CSV files created" -ForegroundColor Red
    }
} else {
    Write-Host "No CSV files found" -ForegroundColor Red
}
