$apiKey = "xUkXFjz3x+Wvtjpjyf+aJzKkDhCJT9rRZmEWBoRroOE="
$headers = @{ 'X-API-Key' = $apiKey }

Write-Host "Testing concurrency endpoint..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/system/test/concurrency?delay=1&id=test" `
        -Method Get `
        -Headers $headers `
        -TimeoutSec 10

    Write-Host "SUCCESS! Response:" -ForegroundColor Green
    $response | ConvertTo-Json
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
}
