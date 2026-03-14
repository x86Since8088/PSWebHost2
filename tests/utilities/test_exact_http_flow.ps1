# Test exact HTTP bearer token flow
Write-Host "=== Exact HTTP Flow Test ===" -ForegroundColor Cyan

. "$PSScriptRoot\..\..\WebHost.ps1" -InitializeEnvironmentOnly 3>$null 4>$null 6>$null | Out-Null

# Create test token
$token = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles 'debug','system_admin' 2>$null
Write-Host "Token: $($token.ApiKey.Substring(0,20))..." -ForegroundColor Green

# STEP 1: Simulate Process-HttpRequest - create unauthenticated session
$sessionID = [Guid]::NewGuid().ToString()
$global:PSWebSessions[$sessionID] = [hashtable]::Synchronized(@{
    UserID = ""
    Provider = ""
    UserAgent = "Test"
    AuthTokenExpiration = (Get-Date)
    LastUpdated = (Get-Date)
    Roles = [System.Collections.ArrayList]@('unauthenticated')
})
Write-Host "Step 1: Created unauthenticated session" -ForegroundColor Yellow
Write-Host "  Roles: $($global:PSWebSessions[$sessionID].Roles)" -ForegroundColor Gray

# STEP 2: Simulate bearer token validation
$authResult = Test-Authentication_API_Key_Bearer -BearerToken $token.ApiKey -RemoteIP "127.0.0.1"
Write-Host "`nStep 2: Bearer auth result" -ForegroundColor Yellow
Write-Host "  Authenticated: $($authResult.Authenticated)" -ForegroundColor Gray
Write-Host "  Roles: $($authResult.Roles -join ', ')" -ForegroundColor Gray

# STEP 3: Simulate line 785-795 - update session
$global:PSWebSessions[$sessionID] = [hashtable]::Synchronized(@{
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
Write-Host "`nStep 3: Updated session with bearer auth" -ForegroundColor Yellow
Write-Host "  Direct access Roles: $($global:PSWebSessions[$sessionID].Roles)" -ForegroundColor Gray
Write-Host "  Direct access Roles type: $($global:PSWebSessions[$sessionID].Roles.GetType().FullName)" -ForegroundColor DarkGray

# STEP 4: Simulate line 808 - Get-PSWebSessions
$Session = Get-PSWebSessions -SessionID $sessionID
Write-Host "`nStep 4: Retrieved via Get-PSWebSessions" -ForegroundColor Yellow
Write-Host "  Session type: $($Session.GetType().FullName)" -ForegroundColor Gray
Write-Host "  Session.Roles: $($Session.Roles)" -ForegroundColor Gray
Write-Host "  Session.Roles type: $($Session.Roles.GetType().FullName)" -ForegroundColor DarkGray

# STEP 5: Simulate app role check (lines 830-843)
$requiredRoles = @('debug', 'system_admin')
$hasRequiredRole = $false
Write-Host "`nStep 5: App role check" -ForegroundColor Yellow
foreach ($reqRole in $requiredRoles) {
    Write-Host "  Checking '$reqRole': " -NoNewline -ForegroundColor Gray
    if ($Session.Roles -contains $reqRole) {
        Write-Host "FOUND" -ForegroundColor Green
        $hasRequiredRole = $true
        break
    } else {
        Write-Host "NOT FOUND" -ForegroundColor Red
    }
}

# STEP 6: Simulate Authorize-Request (lines 275-288)
$securityConfig = @{ Allowed_Roles = @('debug', 'system_admin') }
$userRoles = $Session.Roles
$isAuthorized = $false
Write-Host "`nStep 6: Endpoint security check" -ForegroundColor Yellow
Write-Host "  Security config: $($securityConfig.Allowed_Roles -join ', ')" -ForegroundColor Gray
Write-Host "  User roles: $($userRoles -join ', ')" -ForegroundColor Gray

foreach ($allowedRole in $securityConfig.Allowed_Roles) {
    Write-Host "  Checking '$allowedRole': " -NoNewline -ForegroundColor Gray
    if ($userRoles -contains $allowedRole) {
        Write-Host "MATCH!" -ForegroundColor Green
        $isAuthorized = $true
        break
    } else {
        Write-Host "NO MATCH" -ForegroundColor Red
    }
}

Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan
Write-Host "App role check: " -NoNewline; if ($hasRequiredRole) { Write-Host "PASS" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }
Write-Host "Endpoint security: " -NoNewline; if ($isAuthorized) { Write-Host "PASS" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }

# Cleanup
$global:PSWebSessions.Remove($sessionID)
& "$PSScriptRoot\system\utility\Account_Auth_BearerToken_Remove.ps1" -KeyID $token.KeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null

if ($hasRequiredRole -and $isAuthorized) {
    Write-Host "`n✓ ALL CHECKS PASS - SHOULD WORK!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ CHECKS FAILED - WOULD GET 401" -ForegroundColor Red
    exit 1
}
