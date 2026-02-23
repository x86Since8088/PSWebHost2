#Requires -Version 7

# Create test token with debug role
Write-Host "Creating test token with debug role..." -ForegroundColor Cyan

$tokenResult = & "C:\SC\PsWebHost\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles debug,admin,authenticated

if (-not $tokenResult.Success) {
    Write-Error "Failed to create token: $($tokenResult.Error)"
    exit 1
}

$token = $tokenResult.BearerToken
Write-Host "Token created: $token" -ForegroundColor Green

# Test the poll endpoint
$uri = "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/poll"

try {
    $headers = @{
        Authorization = "Bearer $token"
    }

    $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -UseBasicParsing

    Write-Host "`nStatus Code: $($response.StatusCode)" -ForegroundColor Cyan

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
            Write-Host ""
        }

        return $data
    } elseif ($response.StatusCode -eq 204) {
        Write-Host "No commands in queue (204 No Content)" -ForegroundColor Yellow
    }

} catch {
    Write-Error "Failed to poll: $_"
    Write-Host "Error Details:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    # Note: Token cleanup not implemented - test tokens will remain in database
}
