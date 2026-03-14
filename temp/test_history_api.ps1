$token = "JZLjXYRTy8rKgoMQEP00FlNGikpDMEctFwR30aSAKyo="
$headers = @{ Authorization = "Bearer $token" }

Write-Host "Testing history API with 1h timerange..." -ForegroundColor Cyan
$rawResponse = Invoke-WebRequest -Uri "http://localhost:8080/apps/WebHostMetrics/api/v1/metrics/history?timerange=1h&metrics=cpu" -Headers $headers -UseBasicParsing
Write-Host "Raw response length: $($rawResponse.Content.Length)" -ForegroundColor Gray
Write-Host "`nRaw JSON (first 500 chars):" -ForegroundColor Cyan
Write-Host $rawResponse.Content.Substring(0, [Math]::Min(500, $rawResponse.Content.Length))
$response = $rawResponse.Content | ConvertFrom-Json

Write-Host "Status: $($response.status)" -ForegroundColor Yellow
Write-Host "Start: $($response.startTime)" -ForegroundColor Yellow
Write-Host "End: $($response.endTime)" -ForegroundColor Yellow
Write-Host "Granularity: $($response.granularity)" -ForegroundColor Yellow
Write-Host "Format: $($response.format)" -ForegroundColor Yellow
Write-Host "Sources: $($response.sources)" -ForegroundColor Yellow

if ($response.data) {
    Write-Host "`nData type: $($response.data.GetType().Name)" -ForegroundColor Cyan
    Write-Host "Data.cpu exists: $($null -ne $response.data.cpu)" -ForegroundColor Cyan

    $cpuData = $response.data.cpu
    if ($cpuData) {
        $lines = ($cpuData -split "`n")
        Write-Host "CPU data: $($lines.Count) lines" -ForegroundColor Green
        Write-Host "First 5 lines:" -ForegroundColor Gray
        $lines | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "CPU: NO DATA" -ForegroundColor Red
    }
} else {
    Write-Host "`nNo data in response!" -ForegroundColor Red
}
