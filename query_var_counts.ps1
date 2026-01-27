$token = 'cwJElzqM7pj7tjV7mdI3jjGOENt7KyGfdl2ycFhZXZQ='
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type' = 'application/json'
}

$variables = @(
    @{Name='PSWebSessions'; Command='$Global:PSWebSessions.Count'}
    @{Name='PSWebServer'; Command='$Global:PSWebServer.Count'}
    @{Name='LogHistory'; Command='$Global:LogHistory.Count'}
    @{Name='PSDefaultParameterValues'; Command='$Global:PSDefaultParameterValues.Count'}
    @{Name='Error'; Command='$Global:Error.Count'}
    @{Name='PSVersionTable'; Command='$Global:PSVersionTable.Count'}
)

foreach ($var in $variables) {
    try {
        Write-Host "Querying $($var.Name)..." -ForegroundColor Cyan
        $body = @{
            command = $var.Command
        } | ConvertTo-Json

        $result = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' -Method Post -Headers $headers -Body $body -TimeoutSec 10
        Write-Host "$($var.Name) Count: $($result.result)" -ForegroundColor Green
    }
    catch {
        Write-Host "$($var.Name) : ERROR - $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 200
}
