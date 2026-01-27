# Test Server Response - Check if server is processing requests
Write-Host "`n=== Testing Server Response ===" -ForegroundColor Cyan

$port = 8080
$testUrl = "http://localhost:$port/api/v1/metrics"

Write-Host "Testing: $testUrl" -ForegroundColor Yellow
Write-Host "Timeout: 5 seconds`n" -ForegroundColor Gray

try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $testUrl -TimeoutSec 5 -UseBasicParsing
    $sw.Stop()

    Write-Host "✓ SUCCESS!" -ForegroundColor Green
    Write-Host "  Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
    Write-Host "  Time: $($sw.ElapsedMilliseconds)ms" -ForegroundColor Gray
    Write-Host "  Content-Type: $($response.Headers['Content-Type'])" -ForegroundColor Gray
    Write-Host "  Content Length: $($response.Content.Length) bytes" -ForegroundColor Gray

    # Parse JSON if applicable
    if ($response.Headers['Content-Type'] -match 'json') {
        $json = $response.Content | ConvertFrom-Json
        Write-Host "`n  Response Preview:" -ForegroundColor Cyan
        $json | ConvertTo-Json -Depth 2 | Write-Host -ForegroundColor Gray
    }

    return $true
} catch [System.Net.WebException] {
    Write-Host "✗ Request Failed!" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.Response) {
        Write-Host "  Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Yellow
    }

    return $false
} catch {
    Write-Host "✗ Unexpected Error!" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Type: $($_.Exception.GetType().FullName)" -ForegroundColor Gray

    return $false
}
