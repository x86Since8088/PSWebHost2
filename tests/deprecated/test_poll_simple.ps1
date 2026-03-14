#Requires -Version 7

# Use the token we just created
$token = "6OQXSDf05WJTFMaNPGxHE8qB4kWY+y2xNUs0is3yiQY="

# Test the poll endpoint
$uri = "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/poll"

try {
    $headers = @{
        Authorization = "Bearer $token"
    }

    Write-Host "Polling endpoint: $uri" -ForegroundColor Cyan

    $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -UseBasicParsing

    Write-Host "`nStatus Code: $($response.StatusCode)" -ForegroundColor Green

    if ($response.StatusCode -eq 200) {
        Write-Host "Content:" -ForegroundColor Cyan
        Write-Host $response.Content -ForegroundColor Yellow

        $data = $response.Content | ConvertFrom-Json
        Write-Host "`nParsed Commands:" -ForegroundColor Green
        $data.commands | ForEach-Object {
            Write-Host "  CommandID: $($_.CommandID)" -ForegroundColor White
            Write-Host "  Type: $($_.Type)" -ForegroundColor White
            Write-Host "  Command: $($_.Command)" -ForegroundColor White
            Write-Host "  Status: $($_.Status)" -ForegroundColor White
            Write-Host "  ExecutedAt: $($_.ExecutedAt)" -ForegroundColor White
            Write-Host ""

            # Return this for further testing
            return $_
        }
    } elseif ($response.StatusCode -eq 204) {
        Write-Host "No commands in queue (204 No Content)" -ForegroundColor Yellow
    }

} catch {
    Write-Error "Failed to poll: $_"
    if ($_.Exception.Response) {
        Write-Host "Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
    Write-Host "Error Details:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
