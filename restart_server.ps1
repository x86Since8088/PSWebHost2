#Requires -Version 7

# Kill any processes using port 8080
Write-Host "Checking for processes on port 8080..." -ForegroundColor Yellow
$connections = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
if ($connections) {
    $processes = $connections | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($processId in $processes) {
        Write-Host "  Killing process $processId..." -ForegroundColor Yellow
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  Processes killed" -ForegroundColor Green
    Start-Sleep -Seconds 2
} else {
    Write-Host "  No processes found on port 8080" -ForegroundColor Green
}

# Start WebHost
Write-Host "Starting WebHost.ps1..." -ForegroundColor Cyan
Start-Process pwsh -ArgumentList "-NoExit", "-File", "C:\SC\PsWebHost\WebHost.ps1" -WindowStyle Normal

Write-Host "WebHost.ps1 started in new window" -ForegroundColor Green
