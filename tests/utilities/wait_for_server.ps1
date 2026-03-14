# Wait for server to come online
Write-Host "Waiting for server to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$maxAttempts = 12
for ($i = 1; $i -le $maxAttempts; $i++) {
    try {
        $response = Invoke-WebRequest -Uri 'http://localhost:8080' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Host "Server is online!" -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "Attempt $i/$maxAttempts - Server not ready yet..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

Write-Host "Server did not come online within timeout" -ForegroundColor Red
exit 1
