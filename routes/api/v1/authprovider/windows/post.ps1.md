# routes/api/v1/authprovider/windows/post.ps1

POST endpoint handler for Windows integrated authentication in the PsWebHost system.

## Overview

This route processes user login attempts using Windows domain credentials (username and password). It validates credentials against the Windows operating system, checks for account lockouts, and establishes a session upon successful authentication.

## Endpoint

```
POST /api/v1/authprovider/windows?state={state}&RedirectTo={url}
Content-Type: application/x-www-form-urlencoded

username={username}&password={password}
```

## Parameters

### Route Parameters
```powershell
[cmdletbinding()]
param (
    [System.Net.HttpListenerContext]$Context,
    $SessionData,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)
```

### Query String Parameters
- **state**: OAuth state parameter for CSRF protection (passed to subsequent redirects)
- **RedirectTo**: Optional URL to redirect to after successful authentication

### POST Body Parameters (form-urlencoded)
- **username**: Windows username in UPN format (`user@domain` or `user@localhost`)
- **password**: Windows password (plain text, validated against AD)

## Username Format Handling

The script supports multiple username formats and normalizes them:

```powershell
if ($username -like '*@localhost') {
    $username = $username -replace '@localhost', ("@" + $Env:computername)
}
```

**Supported formats:**
- `user@domain.com` - Standard UPN format
- `user@localhost` - Converted to `user@COMPUTERNAME` for local accounts
- `domain\user` - Traditional domain format (handled by Windows auth)

**Normalization:**
```powershell
$credential = [PSCredential]::new($username, (ConvertTo-SecureString $password -AsPlainText -Force))
$UserPrincipalName = $credential.GetNetworkCredential().UserName + '@' + ($credential.GetNetworkCredential().Domain)
```

## Request Flow

### 1. Parse Request Data

```powershell
$ipAddress = $Request.RemoteEndPoint.Address.ToString()
$bodyContent = Get-RequestBody -Request $Request
$parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
$username = $parsedBody["username"]
$password = $parsedBody["password"]
```

Extracts credentials from POST body and captures client IP for logging.

### 2. Input Validation

**Username Validation:**
```powershell
$IsUserNameValid = Test-IsValidEmailAddress -Email $username -AddCustomRegex '[a-zA-Z0-9._\+\-]+@[a-zA-Z0-9.\-]+'

if ([string]::IsNullOrEmpty($username)) {
    $fail+='<p class="error">Username is required.</p>'
} elseif (-not ($IsUserNameValid.isValid)) {
    $Fail += "<p class=""error"">$($IsUserNameValid.Message)</p>"
}
```

Uses custom regex that allows UPN and domain formats (more permissive than email validation).

**Password Validation:**
```powershell
if ([string]::IsNullOrEmpty($password)) {
    $fail+='<p class="error">Password is required.</p>'
} else {
    $passwordValidation = Test-IsValidPassword -Password $password -Numbers 0
    if (-not $passwordValidation.IsValid) {
        $Fail += "<p class='error'>$($passwordValidation.Message)</p>"
    }
}
```

**Note:** `-Numbers 0` parameter relaxes digit requirements for Windows passwords.

**Validation Failure Response:**
```json
HTTP 400 Bad Request
Content-Type: application/json

{
  "status": "fail",
  "Message": "<p class='error'>Username is required.</p><br><p class='error'>Password is required.</p>"
}
```

### 3. Check for Lockouts

```powershell
$lockoutStatus = Test-LoginLockout -IPAddress $ipAddress -Username $username
write-pswebhostlog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Lockout status for $username from $ipAddress: LockedOut=$(($lockoutStatus).LockedOut); Message='$(($lockoutStatus).Message)'" -Data @{
    IPAddress = $ipAddress;
    Username = $username
    lockoutStatus = $lockoutStatus
    retryAfter = ($lockoutStatus).LockedUntil|Where-Object{$_}|ForEach-Object{$_.ToString("o")}
} -WriteHost

if ($lockoutStatus.LockedOut) {
    $retryAfter = $lockoutStatus.LockedUntil.ToString("o")
    $jsonResponse = New-JsonResponse -status 'fail' -message "<p class='error'>$($lockoutStatus.Message)</p>"
    $Response.AddHeader("Retry-After", $retryAfter)
    context_reponse -Response $Response -StatusCode 429 -String $jsonResponse -ContentType "application/json"
    return
}
```

Detailed lockout logging helps diagnose authentication issues.

**Lockout Response:**
```json
HTTP 429 Too Many Requests
Retry-After: 2025-12-29T12:00:00.0000000Z
Content-Type: application/json

{
  "status": "fail",
  "Message": "<p class='error'>Account locked due to multiple failed login attempts. Try again after [timestamp].</p>"
}
```

### 4. Authenticate Against Windows

```powershell
$credential = New-Object System.Management.Automation.PSCredential($username, (ConvertTo-SecureString $password -AsPlainText -Force))
$AuthTestScript = Join-Path $global:PSWebServer.Project_Root.Path "\system\auth\Test-PSWebWindowsAuth.ps1"
Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Running '\system\auth\Test-PSWebWindowsAuth.ps1'" -Verbose
$isAuthenticated = & $AuthTestScript -credential $credential
Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed '\system\auth\Test-PSWebWindowsAuth.ps1'" -Verbose
```

**Authentication Process:**
1. Creates PSCredential object from username and password
2. Calls `system\auth\Test-PSWebWindowsAuth.ps1` with credential
3. Test script validates against Windows using `[System.DirectoryServices.AccountManagement]` API
4. Returns `$true` if credentials are valid, `$false` otherwise

See also: `system/auth/Test-PSWebWindowsAuth.ps1` for implementation details

### 5a. On Success - Establish Session

```powershell
if ($isAuthenticated) {
    Write-Verbose "$($MyTag) Authentication successful for $($UserPrincipalName)."

    # Look up user by Email (UPN) to get the actual UserID (GUID)
    Write-Verbose "$($MyTag) Looking up user by Email: $($UserPrincipalName)"
    $user = Get-PSWebUser -Email $UserPrincipalName
    if (-not $user) {
        Write-Error "$($MyTag) User not found in database for Email: $($UserPrincipalName). User must be registered before Windows authentication."
        $jsonResponse = New-JsonResponse -status 'fail' -message '<p class="error">User not found. Please contact administrator to register your Windows account.</p>'
        context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
        return
    }
    $actualUserID = $user.UserID
```

**Important:** Windows authentication requires the user to be pre-registered in the database:
- User must exist in `Users` table with `Email` matching UPN
- User must have entry in `auth_user_provider` table with `provider='Windows'`
- Use `system/utility/Account_AuthProvider_Windows_New.ps1` to register Windows users

**User Lookup:**
```powershell
$user = Get-PSWebUser -Email $UserPrincipalName  # e.g., "jdoe@domain.com"
```

Returns user object with `UserID`, `Email`, `Roles`, etc.

**Session Update:**
```powershell
Write-Verbose "$($MyTag) Calling: Set-PSWebSession -SessionID $sessionID -UserID $($actualUserID) -Provider 'Windows' -Request $Request"
Set-PSWebSession -SessionID $sessionID -UserID $actualUserID -Provider 'Windows' -Request $Request
Write-Verbose "$($MyTag) Completed: Set-PSWebSession"
```

Sets session data with authenticated user information and Provider='Windows'.

**Cookie Re-Set:**
```powershell
try {
    $cookie = New-Object System.Net.Cookie('PSWebSessionID', $sessionID)
    $hostName = $Request.Url.HostName
    if ($hostName -notmatch '^(localhost|(\d{1,3}\.){3}\d{1,3}|::1)$') { $cookie.Domain = $hostName }
    $cookie.Path = '/'
    $cookie.HttpOnly = $true
    $cookie.Expires = (Get-Date).AddDays(7)
    $cookie.Secure = $Request.IsSecureConnection
    $Response.AppendCookie($cookie)
    Write-Verbose "$($MyTag) Appended Set-Cookie for session on auth success: $($sessionID)"
} catch {
    Write-Verbose "$($MyTag) Failed to append cookie on auth success: $($_)"
}
```

Explicitly re-sets the session cookie to ensure it persists after redirect.

**Cookie Settings:**
- **HttpOnly**: `true` - Prevents JavaScript access (XSS protection)
- **Secure**: Set if connection is HTTPS
- **Expires**: 7 days from authentication
- **Domain**: Set to hostname (unless localhost/IP)
- **Path**: `/` (all routes)

**MFA Note:**
Multi-factor authentication flow is currently disabled:
```powershell
# MFA FLOW DISABLED - Completing login directly.
Write-Warning "$MyTag MFA check has been temporarily disabled in this route."
```

**Success Response:**
```
HTTP 302 Found
Location: /api/v1/auth/getaccesstoken?state={state}&RedirectTo={url}
Set-Cookie: PSWebSessionID={sessionID}; Path=/; HttpOnly; Expires=...
```

Client is redirected to access token endpoint.

### 5b. On Failure - Log and Reject

```powershell
} else {
    Write-Verbose "$($MyTag) Calling: PSWebLogon -ProviderName ""Windows"" -Result ""Fail"" -Request $Request -UserID $($username)"
    PSWebLogon -ProviderName "Windows" -Result "Fail" -Request $Request -UserID $username
    Write-Verbose "$($MyTag) Completed: PSWebLogon"

    $jsonResponse = New-JsonResponse -status 'fail' -message '<p class="error">Authentication failed. Please check your credentials.</p>'
    context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
}
```

**Failure Response:**
```json
HTTP 401 Unauthorized
Content-Type: application/json

{
  "status": "fail",
  "Message": "<p class='error'>Authentication failed. Please check your credentials.</p>"
}
```

**Security Note:** Error message is intentionally generic to prevent username enumeration.

### 6. Error Handling

```powershell
} catch {
    write-pswebhostlog -Severity 'Error' -Category 'Auth' -Message "$($MyTag) Exception during Windows authentication POST: $($_.Exception.Message)" -Data @{ IPAddress = $ipAddress; Body = $bodyContent } -WriteHost
    PSWebLogon -ProviderName "Windows" -Result "error" -Request $Request

    $jsonResponse = New-JsonResponse -status 'fail' -message "An internal error occurred: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)"
    context_reponse -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
}
```

**Error Response:**
```json
HTTP 500 Internal Server Error
Content-Type: application/json

{
  "status": "fail",
  "Message": "An internal error occurred: [exception message]\n[stack trace]"
}
```

## Response Status Codes

| Code | Meaning | Trigger |
|------|---------|---------|
| 302 | Found (Redirect) | Successful authentication |
| 400 | Bad Request | Validation failure (missing/invalid username or password) |
| 401 | Unauthorized | Invalid credentials or user not registered |
| 429 | Too Many Requests | Account or IP is locked out |
| 500 | Internal Server Error | Unexpected exception during processing |

## Dependencies

### Required Modules
```powershell
Import-Module PSWebHost_Authentication -DisableNameChecking
Import-Module PSWebHost_Database -DisableNameChecking
```

### Functions Used

From **PSWebHost_Authentication**:
- `Test-IsValidEmailAddress` - Validates username format with custom regex
- `Test-IsValidPassword` - Validates password with relaxed digit requirements
- `Test-LoginLockout` - Checks if user or IP is locked out
- `Get-PSWebUser` - Retrieves user record by email/UPN
- `Set-PSWebSession` - Updates session with authenticated user data
- `PSWebLogon` - Logs authentication attempts to database

From **PSWebHost_Support**:
- `Get-RequestBody` - Reads POST body from HttpListenerRequest
- `Write-PSWebHostLog` - Logs messages to TSV log file
- `context_reponse` - Sends HTTP response with status code and content

### External Scripts
- `system/auth/Test-PSWebWindowsAuth.ps1` - Windows credential validation script

## Logging

### Processing Start
```powershell
Write-Host "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Processing Windows authentication POST from $($ipAddress)"
```

### Lockout Check
```powershell
write-pswebhostlog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Lockout status for $username from $ipAddress: LockedOut=$(($lockoutStatus).LockedOut); Message='$(($lockoutStatus).Message)'"
```

### Authentication Attempt
```powershell
Write-Verbose "$($MyTag) Running '\system\auth\Test-PSWebWindowsAuth.ps1'" -Verbose
Write-Verbose "$($MyTag) Completed '\system\auth\Test-PSWebWindowsAuth.ps1'" -Verbose
```

### Success
```powershell
Write-Verbose "$($MyTag) Authentication successful for $($UserPrincipalName)."
Write-Verbose "$($MyTag) Calling: Set-PSWebSession..."
Write-Verbose "$($MyTag) Completed: Set-PSWebSession"
```

### Failure
```powershell
Write-Verbose "$($MyTag) Calling: PSWebLogon -ProviderName ""Windows"" -Result ""Fail""..."
```

### Errors
```powershell
write-pswebhostlog -Severity 'Error' -Category 'Auth' -Message "$($MyTag) Exception during Windows authentication POST: $($_.Exception.Message)"
```

All logs written to `PsWebHost_Data/Logs/log.tsv`

## Security Features

1. **Windows Active Directory Integration**
   - Credentials validated against Windows/AD using native APIs
   - Supports both domain and local accounts
   - No password storage required (delegated to Windows)

2. **Brute-Force Protection**
   - Login lockout after failed attempts
   - Escalating lockout durations
   - Both IP-based and user-based lockouts

3. **Input Validation**
   - Username format validation (UPN or domain\user)
   - Password validation (high-risk Unicode detection)
   - HTML encoding for error messages

4. **User Registration Requirement**
   - Users must be pre-registered in database
   - Prevents unauthorized Windows users from accessing system
   - Requires admin action to enable Windows auth for a user

5. **Session Security**
   - HttpOnly cookies prevent XSS attacks
   - Secure flag set for HTTPS connections
   - 7-day expiration with server-side session storage
   - Cookie re-set on successful auth ensures persistence

6. **CSRF Protection**
   - `state` parameter passed through auth flow
   - Validated in subsequent redirects

## Usage Example

### HTML Login Form

```html
<form action="/api/v1/authprovider/windows?state=abc123&RedirectTo=/dashboard" method="POST">
  <input type="text" name="username" placeholder="user@domain.com" required>
  <input type="password" name="password" placeholder="Password" required>
  <button type="submit">Log In with Windows</button>
</form>
```

### JavaScript Fetch

```javascript
const formData = new URLSearchParams();
formData.append('username', 'jdoe@domain.com');
formData.append('password', 'MyWindowsPassword');

fetch('/api/v1/authprovider/windows?state=abc123&RedirectTo=/dashboard', {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: formData,
  credentials: 'include',  // Include cookies
  redirect: 'follow'       // Follow 302 redirect
})
.then(response => {
  if (response.ok) {
    // Successfully authenticated and redirected
  } else {
    return response.json();
  }
})
.then(data => {
  if (data) {
    console.error('Authentication failed:', data.Message);
  }
});
```

## User Registration

Before a Windows user can authenticate, they must be registered:

```powershell
# Register Windows user
.\system\utility\Account_AuthProvider_Windows_New.ps1 -Email "jdoe@domain.com"
```

This script:
1. Creates user record in `Users` table
2. Adds entry in `auth_user_provider` table with `provider='Windows'`
3. Optionally creates local Windows account for testing

## Testing

### Test Windows Authentication

```powershell
# Test credential validation script directly
.\system\auth\Test-PSWebWindowsAuth.ps1 -credential (Get-Credential)
```

### Create Test User

```powershell
# Create local Windows account for testing
.\system\utility\Account_AuthProvider_Windows_New.ps1 -Email "testuser@localhost"
```

## Troubleshooting

### "User not found" Error

**Cause:** User exists in Windows/AD but not registered in PsWebHost database.

**Solution:** Register the user:
```powershell
.\system\utility\Account_AuthProvider_Windows_New.ps1 -Email "user@domain.com"
```

### Authentication Fails for Valid Credentials

**Possible Causes:**
1. User account disabled in Windows
2. User account locked in Active Directory
3. Domain controller unreachable
4. Incorrect UPN format

**Debugging:**
```powershell
# Test Windows auth script directly
$cred = Get-Credential
.\system\auth\Test-PSWebWindowsAuth.ps1 -credential $cred -Verbose
```

### Session Cookie Not Persisting

**Cause:** Cookie domain mismatch or browser security settings.

**Check:** Look for cookie re-set logging:
```
Appended Set-Cookie for session on auth success: {sessionID}
```

## Related Files

- `system/auth/Test-PSWebWindowsAuth.ps1` - Windows credential validation implementation
- `system/utility/Account_AuthProvider_Windows_New.ps1` - User registration utility
- `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1` - Authentication functions
- `modules/PSWebHost_Database/PSWebHost_Database.psm1` - Database access
- `routes/api/v1/auth/getaccesstoken/post.ps1` - Access token issuance (redirect target)
- `PsWebHost_Data/Logs/log.tsv` - Authentication logs

## Future Enhancements

1. **MFA Support** - Re-enable multi-factor authentication flow
2. **Auto-Registration** - Automatically register Windows users on first login
3. **Group Synchronization** - Sync AD group memberships to PsWebHost roles
4. **Kerberos Authentication** - Support negotiate/NTLM for true SSO
5. **LDAP Integration** - Support non-Windows LDAP directories

## See Also

- Windows authentication test: `system/auth/Test-PSWebWindowsAuth.ps1`
- User registration utility: `system/utility/Account_AuthProvider_Windows_New.ps1`
- Session management: `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1` (Set-PSWebSession)
- Login lockout logic: `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1:727-815`
