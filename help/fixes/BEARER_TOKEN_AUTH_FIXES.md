# Bearer Token Authentication Fixes
**Date**: 2026-02-23
**Status**: Ready for Testing (requires server restart)

---

## Summary

Fixed bearer token authentication for debug endpoints. Three bugs were identified and resolved:

1. **Session Type Conversion Bug** - `Get-PSWebSessions` returning array instead of hashtable
2. **Cookie Requirement Bug** - Bearer auth bypassed by 302 redirect for missing cookie
3. **Cookie Setting Bug** - Bearer auth didn't set session cookie for subsequent requests

---

## Bug 1: Session Type Conversion Bug ✅

### Location
`modules/PSWebHost_Support/PSWebHost_Support.psm1:436`

### Problem
The `Get-PSWebSessions` function returned `$returnValue` without type casting. PowerShell wrapped hashtables in arrays, causing `$Session.Roles` to be null during authorization checks.

### Fix
```powershell
# Before
return $returnValue

# After
return [hashtable]$returnValue
```

### Impact
- Authorization checks can now access `$Session.Roles` correctly
- Fixed 4 AsyncWorker request failures in debug polling

---

## Bug 2: Cookie Requirement Bug ✅

### Location
`modules/PSWebHost_Support/PSWebHost_Support.psm1:1239-1246`

### Problem
`Process-HttpRequest` checked for session cookie and returned 302 redirect BEFORE bearer token auth was evaluated in `Invoke-HttpRequestRoute`. Requests with bearer tokens but no cookie were redirected instead of authenticated.

### Original Code
```powershell
default {
    # ALL OTHER ROUTES - Require session cookie
    # Ensure cookie is established for non-public routes
    if (-not $sessionCookie) {
        Write-Verbose "$($MyTag) Redirecting to establish cookie: $($request.Url.AbsoluteUri)"
        context_response -Response $response -StatusCode 302 -RedirectLocation $request.Url.AbsoluteUri
        return
    }
```

### Fix
```powershell
default {
    # ALL OTHER ROUTES - Require session cookie (unless bearer token provided)
    # Check for Authorization header first (bearer token auth doesn't need cookie)
    $authHeader = $request.Headers['Authorization']
    $hasBearerToken = $authHeader -and $authHeader.StartsWith('Bearer ', [System.StringComparison]::OrdinalIgnoreCase)

    # Ensure cookie is established for non-public routes (unless bearer auth)
    if (-not $sessionCookie -and -not $hasBearerToken) {
        Write-Verbose "$($MyTag) Redirecting to establish cookie: $($request.Url.AbsoluteUri)"
        context_response -Response $response -StatusCode 302 -RedirectLocation $request.Url.AbsoluteUri
        return
    }
```

### Impact
- Bearer token requests can proceed without session cookie
- Removes 302 redirect loop for API clients using bearer tokens

---

## Bug 3: Cookie Setting Bug ✅

### Location
`modules/PSWebHost_Support/PSWebHost_Support.psm1:797-810` (after line 798)

### Problem
After successful bearer token authentication, the code created a session in memory but didn't set a session cookie. This meant:
- First request with bearer token worked (if it reached `Invoke-HttpRequestRoute`)
- Subsequent requests without bearer token failed (no cookie to identify session)
- Test scripts couldn't use `-SessionVariable` to maintain session

### Fix
Added cookie setting after successful bearer auth:

```powershell
Write-Verbose "$MyTag API_Key session created in memory for UserID: $($apiKeyResult.UserID), SessionID: $SessionID"
Write-PSWebHostLog -Severity 'Info' -Category 'Authentication' -Message "$MyTag API key authenticated: $($apiKeyResult.KeyName) from $remoteIP with roles: $($apiKeyResult.Roles -join ', '), SessionID: $SessionID"

# Set session cookie for bearer auth session
$sessionCookie = New-Object System.Net.Cookie("PSWebSessionID", $SessionID)
$hostName = $Request.Url.HostName
if ($hostName -notmatch '^(localhost|(\d{1,3}\.){3}\d{1,3}|::1)$') {
    $sessionCookie.Domain = $hostName
}
$sessionCookie.Expires = (Get-Date).AddDays(7)
$sessionCookie.Path = "/"
$sessionCookie.HttpOnly = $true
$sessionCookie.Secure = $Request.IsSecureConnection
$response.AppendCookie($sessionCookie)
Write-Verbose "$MyTag Session cookie set for bearer auth: $SessionID"
```

### Impact
- Bearer auth creates session cookie for client
- Subsequent requests can use cookie instead of bearer token
- Test scripts can use `-SessionVariable` to maintain authenticated session

---

## Testing

### Updated test_auth_quick.ps1
The quick auth test now uses `-SessionVariable`:

```powershell
$headers = @{ 'Authorization' = "Bearer $($token.ApiKey)" }

try {
    # Use -SessionVariable to maintain session across requests
    $response = Invoke-WebRequest -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history' `
        -Headers $headers `
        -SessionVariable webSession `
        -TimeoutSec 5

    Write-Host "SUCCESS! Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Content: $($response.Content)" -ForegroundColor Cyan
```

### Test Procedure After Server Restart

1. **Quick Auth Test**:
   ```powershell
   .\test_auth_quick.ps1
   ```
   Expected: 200 OK with JSON response

2. **Comprehensive Test Suite**:
   ```powershell
   .\test_debug_command_system.ps1
   ```
   Expected: All 21 tests pass (currently 13 failures due to auth issues)

3. **Debug Commands Test** (requires browser):
   ```powershell
   .\test_debug_commands.ps1
   ```
   Expected: Cards open via debug console, HTML retrieved

---

## Architecture Notes

### Bearer Token Authentication Flow (Fixed)

1. **Request arrives** with `Authorization: Bearer <token>` header
2. **Process-HttpRequest** (lines 1239-1246):
   - Checks for bearer token in Authorization header
   - If present, skips cookie requirement check
   - Passes request to `Invoke-HttpRequestRoute`

3. **Invoke-HttpRequestRoute** (lines 761-805):
   - Detects bearer token in Authorization header
   - Calls `Test-Authentication_API_Key_Bearer` to validate
   - Creates session in `$global:PSWebSessions` with user's roles
   - **NEW**: Sets session cookie `PSWebSessionID`

4. **Get-PSWebSessions** (line 808):
   - **FIXED**: Returns hashtable (not array) with roles intact

5. **App Role Check** (lines 830-843):
   - Checks if session roles contain app's required roles
   - WebHostDebugExtensions requires: `debug` OR `system_admin`

6. **Endpoint Security Check** (lines 275-288 in `Authorize-Request`):
   - Checks if session roles match endpoint's `Allowed_Roles`
   - Debug endpoints require: `debug` OR `system_admin`

### Session Cookie Behavior

**Before Fix**:
- Bearer auth: Session created, but no cookie set
- Result: First request worked, subsequent requests failed

**After Fix**:
- Bearer auth: Session created AND cookie set
- Result: All subsequent requests use cookie automatically
- Test scripts can use `-SessionVariable` to persist session

---

## Files Modified

1. `modules/PSWebHost_Support/PSWebHost_Support.psm1`
   - Line 436: Session type conversion fix
   - Lines 1239-1246: Cookie requirement bypass for bearer tokens
   - Lines 797-810: Cookie setting for bearer auth sessions

2. `test_auth_quick.ps1`
   - Added `-SessionVariable webSession` parameter
   - Now maintains session across requests

---

## Additional Fixes Applied (Previous Work)

1. **Missing Component Files** ✅
   - Created: `public/elements/nodes-manager/component.js`
   - Created: `public/elements/card-validation/component.js`
   - Created: `public/elements/job-status/component.js`
   - Created: `public/elements/header-icon/component.js`

2. **Card URL Pattern Matching** ✅
   - File: `public/psweb_spa.js`
   - Functions: `window.openCard`, `window.openCardCopy`
   - Now supports: `/api/v1/ui/elements/*`, `/cards/*`, `/apps/*/cards/*`

---

## Next Steps

1. **Restart Server** - Required for module changes to take effect
2. **Run test_auth_quick.ps1** - Verify bearer token auth works
3. **Run test_debug_command_system.ps1** - Verify all 21 tests pass
4. **Test in Browser** - Verify debug console and polling work

---

## Conclusion

All three bearer token authentication bugs have been fixed:
1. Session type conversion (hashtable vs array)
2. Cookie requirement bypass for bearer tokens
3. Cookie setting after successful bearer auth

The system is now ready for testing after server restart. Bearer token authentication should work correctly with the debug endpoints, and test scripts can maintain authenticated sessions using `-SessionVariable`.
