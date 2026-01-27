$apiKey = '0Vqgs6LaygeHj9pb1LyQxWPKL32CGiEjpZHEXTml05E='

try {
    $response = Invoke-WebRequest -Uri 'http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit' `
        -Method POST `
        -Headers @{ 'Authorization' = "Bearer $apiKey" } `
        -ContentType 'application/json' `
        -Body '{"jobName":"TestJob","command":"Get-Date","description":"Test","executionMode":"MainLoop"}'

    Write-Host "Success: $($response.StatusCode)" -ForegroundColor Green
    $response.Content
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "Details:" -ForegroundColor Yellow
        $_.ErrorDetails.Message | ConvertFrom-Json | ConvertTo-Json -Depth 5
    }
}
