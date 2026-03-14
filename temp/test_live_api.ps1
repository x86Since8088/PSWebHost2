$token = "JZLjXYRTy8rKgoMQEP00FlNGikpDMEctFwR30aSAKyo="
$headers = @{ Authorization = "Bearer $token" }

Write-Host "Testing history API with 1h timerange..." -ForegroundColor Cyan
$response = Invoke-WebRequest -Uri "http://localhost:8080/apps/WebHostMetrics/api/v1/metrics/history?timerange=1h&metrics=cpu" -Headers $headers -UseBasicParsing

Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
Write-Host "Content length: $($response.Content.Length)"

$data = $response.Content | ConvertFrom-Json
Write-Host "Status: $($data.status)"
Write-Host "Sources: $($data.sources)"
Write-Host "Start: $($data.startTime)"
Write-Host "End: $($data.endTime)"

if ($data.data.cpu) {
    $lines = ($data.data.cpu -split "`n")
    Write-Host "CPU lines: $($lines.Count)" -ForegroundColor Green
    Write-Host "Header: $($lines[0])"
    Write-Host "First data row: $($lines[1])"
    Write-Host "Last data row: $($lines[-1])"
}
