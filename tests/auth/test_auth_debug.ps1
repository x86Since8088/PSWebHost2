# Debug bearer token authentication
Write-Host "=== Bearer Token Authentication Debug ===" -ForegroundColor Cyan

# Create test token
Write-Host "`n1. Creating test bearer token..." -ForegroundColor Yellow
$token = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles 'debug','system_admin'

if (-not $token) {
    Write-Host "Failed to create token" -ForegroundColor Red
    exit 1
}

Write-Host "Token: $($token.ApiKey)" -ForegroundColor Green
Write-Host "UserID: $($token.DedicatedUserID)" -ForegroundColor Gray
Write-Host "Email: $($token.DedicatedEmail)" -ForegroundColor Gray
Write-Host "Roles: $($token.Roles -join ', ')" -ForegroundColor Gray

# Test direct authentication function
Write-Host "`n2. Testing Test-Authentication_API_Key_Bearer function..." -ForegroundColor Yellow

try {
    # Try to call the function directly (requires PSWebHost_Authentication module loaded)
    if (Get-Command Test-Authentication_API_Key_Bearer -ErrorAction SilentlyContinue) {
        $authResult = Test-Authentication_API_Key_Bearer -BearerToken $token.ApiKey -RemoteIP "127.0.0.1"
        Write-Host "Auth Result:" -ForegroundColor Cyan
        $authResult | Format-List | Out-String | Write-Host
    } else {
        Write-Host "Function not available in this context" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test HTTP endpoint with verbose headers
Write-Host "`n3. Testing HTTP endpoint with verbose output..." -ForegroundColor Yellow

$headers = @{ 'Authorization' = "Bearer $($token.ApiKey)" }
$uri = 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history'

Write-Host "URI: $uri" -ForegroundColor Gray
Write-Host "Authorization: Bearer $($token.ApiKey.Substring(0,20))..." -ForegroundColor Gray

try {
    $response = Invoke-WebRequest -Uri $uri `
        -Headers $headers `
        -UseBasicParsing `
        -TimeoutSec 5 `
        -Verbose

    Write-Host "`nSUCCESS!" -ForegroundColor Green
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Content:" -ForegroundColor Cyan
    $response.Content | Write-Host
} catch {
    Write-Host "`nFAILED!" -ForegroundColor Red
    Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

    if ($_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response Body: $responseBody" -ForegroundColor Yellow
        } catch {
            Write-Host "Could not read response body" -ForegroundColor Gray
        }
    }
}

# Cleanup
Write-Host "`n4. Cleaning up..." -ForegroundColor Yellow
& "$PSScriptRoot\system\utility\Account_Auth_BearerToken_Remove.ps1" -KeyID $token.KeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null
Write-Host "Done!" -ForegroundColor Green
