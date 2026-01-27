$token = 'cwJElzqM7pj7tjV7mdI3jjGOENt7KyGfdl2ycFhZXZQ='
$headers = @{
    'Authorization' = "Bearer $token"
    'Content-Type' = 'application/json'
}

$varName = $args[0]

$body = @{
    command = "try{($varName| convertto-json -depth 15).length}catch{`$_.Exception.message}"
} | ConvertTo-Json

$result = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' -Method Post -Headers $headers -Body $body
Write-Output "$varName : $($result.result)"
