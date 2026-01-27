$token = 'cwJElzqM7pj7tjV7mdI3jjGOENt7KyGfdl2ycFhZXZQ='
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type' = 'application/json'
}

Write-Host "Testing simple command first..." -ForegroundColor Cyan
$body = @{
    script = "1 + 1"
} | ConvertTo-Json

try {
    $result = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' -Method Post -Headers $headers -Body $body -TimeoutSec 5
    Write-Host "Simple test result: $($result.output)" -ForegroundColor Green
}
catch {
    Write-Host "Simple test ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`nQuerying variables..." -ForegroundColor Cyan

$variables = @(
    '$Global:PSWebSessions'
    '$Global:PSWebServer'
    '$Global:LogHistory'
    '$Global:PSDefaultParameterValues'
    '$Global:Error'
    '$Global:PSVersionTable'
)

foreach ($varName in $variables) {
    try {
        Write-Host "  Querying $varName..." -NoNewline
        $body = @{
            script = "try{($varName | convertto-json -depth 15).length}catch{`$_.Exception.message}"
            timeout = 30
        } | ConvertTo-Json

        $result = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' -Method Post -Headers $headers -Body $body -TimeoutSec 35

        if ($result.status -eq 'success') {
            Write-Host " $($result.output.Trim()) bytes" -ForegroundColor Green
        }
        else {
            Write-Host " $($result.status) - $($result.message)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " ERROR - $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 200
}
