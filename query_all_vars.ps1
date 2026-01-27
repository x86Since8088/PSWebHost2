$token = 'cwJElzqM7pj7tjV7mdI3jjGOENt7KyGfdl2ycFhZXZQ='
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type' = 'application/json'
}

$variables = @(
    '$Global:PSWebSessions'
    '$Global:PSWebServer'
    '$Global:LogHistory'
    '$Global:PSDefaultParameterValues'
    '$Global:args'
    '$Global:Error'
    '$Global:PSVersionTable'
)

foreach ($varName in $variables) {
    try {
        $body = @{
            command = "try{($varName | convertto-json -depth 15).length}catch{`$_.Exception.message}"
        } | ConvertTo-Json

        $result = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' -Method Post -Headers $headers -Body $body -TimeoutSec 5
        Write-Host "$varName : $($result.result)" -ForegroundColor Green
    }
    catch {
        Write-Host "$varName : ERROR - $($_.Exception.Message)" -ForegroundColor Red
    }
}
