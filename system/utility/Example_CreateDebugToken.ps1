# Example_CreateDebugToken.ps1
# Quick example: Create a debug token and test it with the CLI API

[CmdletBinding()]
param(
    [int]$Port = 8080
)

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Create Debug Token and Test CLI API          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Step 1: Create a test token with debug role
Write-Host "1. Creating test token with debug role..." -ForegroundColor Yellow

$tokenScript = Join-Path $PSScriptRoot "Account_Auth_BearerToken_Get.ps1"
$token = & $tokenScript -Create -TestToken -Roles @('debug', 'authenticated') -Verbose

if (-not $token) {
    Write-Host "✗ Failed to create token" -ForegroundColor Red
    exit 1
}

Write-Host "`n2. Token created successfully!" -ForegroundColor Green
Write-Host "   Bearer Token: $($token.BearerToken)" -ForegroundColor Cyan
Write-Host "   User Email: $($token.UserEmail)" -ForegroundColor Gray
Write-Host "   Roles: $($token.Roles -join ', ')" -ForegroundColor Gray

# Step 2: Test the token with a simple CLI command
Write-Host "`n3. Testing token with CLI API..." -ForegroundColor Yellow

$headers = @{
    'Authorization' = "Bearer $($token.BearerToken)"
    'Content-Type' = 'application/json'
}

$testScript = 'Get-Date | ConvertTo-Json'
$body = @{
    script = $testScript
    timeout = 10
} | ConvertTo-Json

try {
    Write-Host "   Making request to http://localhost:$Port/api/v1/cli..." -ForegroundColor Gray

    $response = Invoke-WebRequest -Uri "http://localhost:$Port/api/v1/cli" `
        -Method POST `
        -Headers $headers `
        -Body $body `
        -TimeoutSec 10 `
        -UseBasicParsing

    $result = $response.Content | ConvertFrom-Json

    if ($result.status -eq 'success') {
        Write-Host "`n✓ CLI API test successful!" -ForegroundColor Green
        Write-Host "   Output:" -ForegroundColor Gray
        Write-Host "   $($result.output)" -ForegroundColor Cyan
    } else {
        Write-Host "`n✗ CLI API returned error:" -ForegroundColor Red
        Write-Host "   $($result.message)" -ForegroundColor Red
    }
} catch {
    Write-Host "`n✗ CLI API test failed:" -ForegroundColor Red
    Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
}

# Step 3: Show how to use for diagnostics
Write-Host "`n4. Example: Using token for server diagnostics..." -ForegroundColor Yellow
Write-Host "   You can now run diagnostics remotely:" -ForegroundColor Gray
Write-Host ""
Write-Host "   .\test_via_cli_api.ps1 -BearerToken '$($token.BearerToken)'" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Or use curl:" -ForegroundColor Gray
Write-Host "   curl -X POST http://localhost:$Port/api/v1/cli \\" -ForegroundColor Cyan
Write-Host "     -H 'Authorization: Bearer $($token.BearerToken)' \\" -ForegroundColor Cyan
Write-Host "     -H 'Content-Type: application/json' \\" -ForegroundColor Cyan
Write-Host "     -d '{\"script\":\"Get-Date\"}'" -ForegroundColor Cyan

# Step 4: Cleanup instructions
Write-Host "`n5. Cleanup (when done testing):" -ForegroundColor Yellow
Write-Host "   .\Account_Auth_BearerToken_Remove.ps1 -KeyID '$($token.KeyID)' -RemoveUser -Force" -ForegroundColor Gray
Write-Host ""
Write-Host "   Or remove all test tokens:" -ForegroundColor Gray
Write-Host "   .\Account_Auth_BearerToken_RemoveTestingTokens.ps1 -Force -RemoveUsers" -ForegroundColor Gray

Write-Host "`n╔════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Token Details Saved to Variable: `$token     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Return the token object for further use
return $token
