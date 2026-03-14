$token = 'cwJElzqM7pj7tjV7mdI3jjGOENt7KyGfdl2ycFhZXZQ='
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type' = 'application/json'
}

Write-Host "Testing simple command..." -ForegroundColor Cyan
$body = @{
    command = "1 + 1"
} | ConvertTo-Json

try {
    $result = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' -Method Post -Headers $headers -Body $body -TimeoutSec 5
    Write-Host "Result: $($result.result)" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
