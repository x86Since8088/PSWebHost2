# Test session creation and retrieval with bearer token
Write-Host "=== Session Debug Test ===" -ForegroundColor Cyan

# Initialize environment
Write-Host "`nLoading PSWebHost environment..." -ForegroundColor Yellow
. "$PSScriptRoot\..\..\WebHost.ps1" -InitializeEnvironmentOnly 3>$null 4>$null 6>$null | Out-Null

# Create test API key
Write-Host "`nCreating test bearer token..." -ForegroundColor Yellow
$token = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles 'debug','system_admin' 2>$null

Write-Host "Token created: $($token.ApiKey.Substring(0,20))..." -ForegroundColor Green
Write-Host "UserID: $($token.DedicatedUserID)" -ForegroundColor Gray
Write-Host "Expected Roles: $($token.Roles -join ', ')" -ForegroundColor Gray

# Test the authentication function
Write-Host "`nTesting Test-Authentication_API_Key_Bearer..." -ForegroundColor Yellow
$authResult = Test-Authentication_API_Key_Bearer -BearerToken $token.ApiKey -RemoteIP "127.0.0.1"

Write-Host "Authenticated: $($authResult.Authenticated)" -ForegroundColor $(if ($authResult.Authenticated) { "Green" } else { "Red" })
Write-Host "UserID: $($authResult.UserID)" -ForegroundColor Gray
Write-Host "Roles from auth: $($authResult.Roles -join ', ')" -ForegroundColor Gray
Write-Host "Roles type: $($authResult.Roles.GetType().FullName)" -ForegroundColor DarkGray

# Simulate what Invoke-HttpRequestRoute does
Write-Host "`nSimulating Invoke-HttpRequestRoute session creation..." -ForegroundColor Yellow
$SessionID = [guid]::NewGuid().ToString()

# This is what line 785-795 does
$global:PSWebSessions[$SessionID] = [hashtable]::Synchronized(@{
    UserID = $authResult.UserID
    Provider = "API_Key"
    UserAgent = "Test"
    AuthTokenExpiration = (Get-Date).AddHours(1)
    LastUpdated = (Get-Date)
    AuthenticationState = "completed"
    Roles = $authResult.Roles
    ApiKeyName = $authResult.KeyName
    ApiKeySource = $authResult.Source
})

Write-Host "Session created in global hashtable" -ForegroundColor Green

# This is what line 808 does
Write-Host "`nRetrieving session with Get-PSWebSessions..." -ForegroundColor Yellow
$Session = Get-PSWebSessions -SessionID $SessionID

Write-Host "Session type: $($Session.GetType().FullName)" -ForegroundColor $(if ($Session -is [hashtable]) { "Green" } else { "Red" })
Write-Host "Session.UserID: $($Session.UserID)" -ForegroundColor Gray
Write-Host "Session.Roles: $($Session.Roles)" -ForegroundColor Gray
Write-Host "Session.Roles type: $(if ($Session.Roles) { $Session.Roles.GetType().FullName } else { 'NULL' })" -ForegroundColor DarkGray
Write-Host "Session.Roles count: $(if ($Session.Roles) { $Session.Roles.Count } else { 0 })" -ForegroundColor DarkGray

# Test the app role check logic (lines 830-843)
Write-Host "`nTesting app role check logic..." -ForegroundColor Yellow
$requiredRoles = @('debug', 'system_admin')
$hasRequiredRole = $false

foreach ($reqRole in $requiredRoles) {
    Write-Host "  Checking for role '$reqRole'..." -ForegroundColor Gray
    Write-Host "    Session.Roles: $($Session.Roles)" -ForegroundColor DarkGray
    Write-Host "    Contains check: $($Session.Roles -contains $reqRole)" -ForegroundColor DarkGray

    if ($Session.Roles -contains $reqRole) {
        Write-Host "    ✓ Found!" -ForegroundColor Green
        $hasRequiredRole = $true
        break
    } else {
        Write-Host "    ✗ Not found" -ForegroundColor Red
    }
}

Write-Host "`nFinal Result: hasRequiredRole = $hasRequiredRole" -ForegroundColor $(if ($hasRequiredRole) { "Green" } else { "Red" })

# Cleanup
$global:PSWebSessions.Remove($SessionID)
& "$PSScriptRoot\system\utility\Account_Auth_BearerToken_Remove.ps1" -KeyID $token.KeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null

if ($hasRequiredRole) {
    Write-Host "`n✓ SESSION AUTHENTICATION WORKING!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ SESSION AUTHENTICATION FAILING!" -ForegroundColor Red
    exit 1
}
