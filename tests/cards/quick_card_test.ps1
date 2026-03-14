# Quick Card Endpoint Test

Write-Host "`n===== Quick Card Test =====" -ForegroundColor Cyan

$testUrl = "http://localhost:8080/cards/system-log"

try {
    Write-Host "Testing: $testUrl" -ForegroundColor Yellow

    # Get session
    $response1 = Invoke-WebRequest -Uri $testUrl -SessionVariable session -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue

    # Get content with session
    $response2 = Invoke-WebRequest -Uri $testUrl -WebSession $session -UseBasicParsing -ErrorAction Stop

    Write-Host "Status: $($response2.StatusCode)" -ForegroundColor Green
    Write-Host "Content Length: $($response2.Content.Length)" -ForegroundColor Green

    $json = $response2.Content | ConvertFrom-Json

    Write-Host "`nJSON Response:" -ForegroundColor Cyan
    Write-Host "  component: $($json.component)" -ForegroundColor White
    Write-Host "  scriptPath: $($json.scriptPath)" -ForegroundColor $(if ($json.scriptPath) { 'Green' } else { 'Red' })
    Write-Host "  title: $($json.title)" -ForegroundColor White

    if ($json.scriptPath) {
        Write-Host "`n✓ SUCCESS: scriptPath field present!" -ForegroundColor Green
    } else {
        Write-Host "`n× FAIL: scriptPath field missing!" -ForegroundColor Red
    }

} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
