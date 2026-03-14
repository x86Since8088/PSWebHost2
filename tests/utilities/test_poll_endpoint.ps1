#Requires -Version 7

# Test the poll endpoint to verify it picks up the command

$uri = "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/poll"

try {
    $response = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing

    Write-Host "Status Code: $($response.StatusCode)" -ForegroundColor Cyan
    Write-Host "Content:" -ForegroundColor Cyan
    Write-Host $response.Content -ForegroundColor Yellow

    if ($response.StatusCode -eq 200) {
        $data = $response.Content | ConvertFrom-Json
        Write-Host "`nParsed Commands:" -ForegroundColor Green
        $data.commands | ForEach-Object {
            Write-Host "  CommandID: $($_.CommandID)" -ForegroundColor White
            Write-Host "  Type: $($_.Type)" -ForegroundColor White
            Write-Host "  Command: $($_.Command)" -ForegroundColor White
            Write-Host "  Status: $($_.Status)" -ForegroundColor White
            Write-Host ""
        }

        return $data
    }

} catch {
    Write-Error "Failed to poll: $_"
    Write-Host "Error Details:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
