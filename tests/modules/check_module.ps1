# Check if the module is loaded in the server
$apiKey = '0Vqgs6LaygeHj9pb1LyQxWPKL32CGiEjpZHEXTml05E='

try {
    # Call CLI API to check if function exists
    $body = @{
        script = "Get-Command Submit-PSWebHostJob -ErrorAction SilentlyContinue | Select-Object Name, ModuleName, Module"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' `
        -Method POST `
        -Headers @{ 'Authorization' = "Bearer $apiKey" } `
        -ContentType 'application/json' `
        -Body $body

    Write-Host "Response:" -ForegroundColor Cyan
    $response | ConvertTo-Json -Depth 5
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        $_.ErrorDetails.Message
    }
}
