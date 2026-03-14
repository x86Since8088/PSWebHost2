try {
    $response = Invoke-WebRequest -Uri 'http://localhost:8080/public/lib/duckdb-browser.mjs' -Method HEAD -UseBasicParsing -TimeoutSec 10
    Write-Host "Status: $($response.StatusCode)"
    Write-Host "Content-Type: $($response.Headers['Content-Type'])"

    if ($response.Headers['Content-Type'] -like '*javascript*') {
        Write-Host "SUCCESS: .mjs file is being served with correct MIME type" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "FAIL: .mjs file has incorrect MIME type" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
