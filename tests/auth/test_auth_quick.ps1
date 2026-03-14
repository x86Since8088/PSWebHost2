# Quick auth test for debug endpoints
Write-Host "Creating test bearer token..." -ForegroundColor Yellow

$token = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles 'debug','system_admin'

if (-not $token) {
    Write-Host "Failed to create token" -ForegroundColor Red
    exit 1
}

Write-Host "Token created: $($token.ApiKey.Substring(0,20))..." -ForegroundColor Green
Write-Host "`nTesting history endpoint..." -ForegroundColor Yellow

$headers = @{ 'Authorization' = "Bearer $($token.ApiKey)" }

try {
    # Use -SessionVariable to maintain session across requests
    $response = Invoke-WebRequest -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history' `
        -Headers $headers `
        -SessionVariable webSession `
        -TimeoutSec 5

    Write-Host "SUCCESS! Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Content: $($response.Content)" -ForegroundColor Cyan
} catch {
    Write-Host "FAILED! Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    }
}

# Cleanup
Write-Host "`nCleaning up..." -ForegroundColor Yellow
& "$PSScriptRoot\system\utility\Account_Auth_BearerToken_Remove.ps1" -KeyID $token.KeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null
Write-Host "Done!" -ForegroundColor Green
