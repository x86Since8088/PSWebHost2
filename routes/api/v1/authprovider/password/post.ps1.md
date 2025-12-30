# routes/api/v1/authprovider/password/post.ps1

POST endpoint handler for password-based authentication in the PsWebHost system.

## Overview

This route processes user login attempts using email/password credentials. It validates inputs, checks for account lockouts, authenticates the user against the database, and establishes a session upon successful authentication.

## Endpoint

```
POST /api/v1/authprovider/password?state={state}
Content-Type: application/x-www-form-urlencoded

email={email}&password={password}&RedirectTo={url}
```

## Parameters

### Route Parameters
```powershell
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request,
    [System.Net.HttpListenerResponse]$Response,
    $sessiondata  # Current session data from PSWebSessionID cookie
)
```

### Query String Parameters
- **state**: OAuth state parameter for CSRF protection (passed to subsequent redirects)

### POST Body Parameters (form-urlencoded)
- **email**: User's email address (used as username)
- **password**: User's password (plain text, validated and hashed server-side)
- **RedirectTo**: Optional URL to redirect to after successful authentication

## Request Flow

### 1. Parse Request Data

```powershell
$ipAddress = $Request.RemoteEndPoint.Address.ToString()
$bodyContent = Get-RequestBody -Request $Request
$parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
$email = $parsedBody["email"]
$password = $parsedBody["password"]
$redirectTo = $parsedBody["RedirectTo"]
```

Extracts credentials from the POST body and captures the client IP address for logging.

### 2. Input Validation

**Email Validation:**
```powershell
$IsEmailValid = Test-IsValidEmailAddress -Email $email
if ([string]::IsNullOrEmpty($email)) {
    $fail+='<p class="error">Email is required.</p>'
} elseif (-not ($IsEmailValid.isValid)) {
    $Fail += "<p class=""error"">$($IsEmailValid.Message)</p>"
}
```

Checks:
- Email field is not empty
- Email format is valid
- No high-risk Unicode characters present

**Password Validation:**
```powershell
if ([string]::IsNullOrEmpty($password)) {
    $fail+='<p class="error">Password is required.</p>'
} else {
    $passwordValidation = Test-IsValidPassword -Password $password
    if (-not $passwordValidation.IsValid) {
        $Fail += "<p class='error'>$($passwordValidation.Message)</p>"
    }
}
```

Checks:
- Password field is not empty
- Password meets complexity requirements (see routes/api/v1/authprovider/password/post.ps1:48)
- No high-risk Unicode characters present

**Validation Failure Response:**
```json
HTTP 422 Unprocessable Entity
Content-Type: application/json

{
  "status": "fail",
  "Message": "<p class='error'>Email is required.</p><br><p class='error'>Password is required.</p>"
}
```

### 3. Check for Lockouts

```powershell
$lockoutStatus = Test-LoginLockout -IPAddress $ipAddress -Username $email
if ($lockoutStatus.LockedOut) {
    $retryAfter = $lockoutStatus.LockedUntil.ToString("o")
    $jsonResponse = New-JsonResponse -status 'fail' -message $lockoutStatus.Message
    $Response.AddHeader("Retry-After", $retryAfter)
    context_reponse -Response $Response -StatusCode 429 -String $jsonResponse -ContentType "application/json"
    return
}
```

Prevents brute-force attacks by checking if the user or IP is locked out due to previous failed attempts.

**Lockout Response:**
```json
HTTP 429 Too Many Requests
Retry-After: 2025-12-29T12:00:00.0000000Z
Content-Type: application/json

{
  "status": "fail",
  "Message": "Account locked due to multiple failed login attempts. Try again after [timestamp]."
}
```

### 4. Authenticate User

```powershell
$isAuthenticated = Invoke-AuthenticationMethod -Name "Password" -FormData @{
    Username = $email
    Password = $password
}
```

Calls the Password authentication method which:
1. Retrieves user from database by email
2. Extracts salt and hash from `PasswordHash` field
3. Hashes provided password with salt using PBKDF2 (10,000 iterations)
4. Compares computed hash with stored hash
5. Returns `$true` if match, `$false` otherwise

### 5a. On Success - Establish Session

```powershell
if ($isAuthenticated) {
    $user = Get-PSWebHostUser -Email $email
    $sessionID = $Context.Request.Cookies["PSWebSessionID"].Value

    # MFA FLOW DISABLED - Completing login directly.
    Write-Warning "MFA check has been temporarily disabled in this route."
    Set-PSWebSession -SessionID $sessionID -UserID $user.UserID -Roles $user.Roles -Provider 'Password' -Request $Request

    $redirectUrl = "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
}
```

**Session Update:**
- Retrieves full user object (including UserID and Roles)
- Updates session with authenticated user data
- Sets Provider to "Password"

**MFA Note:**
Multi-factor authentication flow is currently disabled. In the future, this would check for MFA enrollment:
```powershell
# Future MFA flow (currently disabled):
$mfaProvider = Get-PSWebAuthUserProvider -UserID $user.UserID -Provider 'tokenauthenticator'
if ($mfaProvider -and $mfaProvider.enabled) {
    Set-PSWebSession -SessionID $sessionID -State 'mfa_required' -Provider 'Password'
    $redirectUrl = "/api/v1/auth/mfa?state=$state&RedirectTo=$redirectTo"
}
```

**Success Response:**
```
HTTP 302 Found
Location: /api/v1/auth/getaccesstoken?state={state}&RedirectTo={url}
```

Client is redirected to the access token endpoint which will issue a JWT or session token.

### 5b. On Failure - Log and Reject

```powershell
} else {
    PSWebLogon -ProviderName "Password" -Result "Fail" -Request $Request -UserID $email

    $jsonResponse = New-JsonResponse -status 'fail' -message 'Authentication failed. Please check your credentials.'
    context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
}
```

**Failure Response:**
```json
HTTP 401 Unauthorized
Content-Type: application/json

{
  "status": "fail",
  "Message": "Authentication failed. Please check your credentials."
}
```

**Security Note:** The error message is intentionally generic to prevent username enumeration attacks.

### 6. Error Handling

```powershell
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Auth' -Message "Invalid request body for Password auth POST: $($_.Exception.Message)" -Data @{ IPAddress = $ipAddress; Body = $bodyContent }
    PSWebLogon -ProviderName "Password" -Result "error" -Request $Request

    $jsonResponse = New-JsonResponse -status 'fail' -message "An internal error occurred: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)"
    context_reponse -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
}
```

Catches unexpected errors during processing (database errors, null references, etc.).

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
| 401 | Unauthorized | Invalid credentials |
| 422 | Unprocessable Entity | Validation failure (missing/invalid email or password) |
| 429 | Too Many Requests | Account or IP is locked out |
| 500 | Internal Server Error | Unexpected exception during processing |

## Dependencies

### Required Modules
```powershell
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database")
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Authentication")
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Support")
```

### Functions Used

From **PSWebHost_Authentication**:
- `Test-IsValidEmailAddress` - Validates email format and checks for malicious Unicode
- `Test-IsValidPassword` - Validates password complexity and checks for malicious Unicode
- `Test-LoginLockout` - Checks if user or IP is locked out
- `Invoke-AuthenticationMethod` - Performs PBKDF2 password verification
- `Get-PSWebHostUser` - Retrieves user record from database
- `Set-PSWebSession` - Updates session with authenticated user data
- `PSWebLogon` - Logs authentication attempts to database

From **PSWebHost_Support**:
- `Get-RequestBody` - Reads POST body from HttpListenerRequest
- `Write-PSWebHostLog` - Logs messages to TSV log file
- `context_reponse` - Sends HTTP response with status code and content

## Logging

### Successful Authentication
```powershell
Write-Host "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Processing Password authentication POST from $($ipAddress)"
# Logs via Set-PSWebSession and PSWebLogon
```

### Failed Authentication
```powershell
PSWebLogon -ProviderName "Password" -Result "Fail" -Request $Request -UserID $email
```

### Validation Failures
```powershell
write-pswebhostlog -Severity 'Warning' -Category 'Auth' -Message "$MyTag Validation failed for Password auth POST from $ipAddress. Errors: $($Fail -join '; ')" -Data @{ IPAddress = $ipAddress; Body = $bodyContent } -WriteHost
```

### Errors
```powershell
Write-PSWebHostLog -Severity 'Error' -Category 'Auth' -Message "Invalid request body for Password auth POST: $($_.Exception.Message)" -Data @{ IPAddress = $ipAddress; Body = $bodyContent }
```

All logs are written to `PsWebHost_Data/Logs/log.tsv`

## Security Features

1. **Input Validation**
   - Email format validation
   - Password complexity requirements
   - High-risk Unicode character detection
   - HTML encoding for error messages

2. **Brute-Force Protection**
   - Login lockout after failed attempts (see `Test-LoginLockout`)
   - Escalating lockout durations based on violation count
   - Both IP-based and user-based lockouts

3. **Credential Protection**
   - Passwords hashed using PBKDF2 with 10,000 iterations
   - Per-user salts stored with hash
   - Plain-text passwords never stored or logged

4. **Generic Error Messages**
   - "Authentication failed" rather than "User not found" or "Incorrect password"
   - Prevents username enumeration attacks

5. **CSRF Protection**
   - `state` parameter passed through authentication flow
   - Validated in subsequent redirects

6. **Session Security**
   - Session ID stored in HttpOnly cookie
   - Session data stored server-side
   - Session tied to IP address and user agent

## Usage Example

### HTML Login Form

```html
<form action="/api/v1/authprovider/password?state=abc123" method="POST">
  <input type="email" name="email" placeholder="Email" required>
  <input type="password" name="password" placeholder="Password" required>
  <input type="hidden" name="RedirectTo" value="/dashboard">
  <button type="submit">Log In</button>
</form>
```

### JavaScript Fetch

```javascript
const formData = new URLSearchParams();
formData.append('email', 'user@example.com');
formData.append('password', 'MySecurePassword123!');
formData.append('RedirectTo', '/dashboard');

fetch('/api/v1/authprovider/password?state=abc123', {
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

## Related Files

- `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1` - Authentication functions
- `modules/PSWebHost_Database/PSWebHost_Database.psm1` - Database access
- `routes/api/v1/auth/getaccesstoken/post.ps1` - Access token issuance (redirect target)
- `system/db/sqlite/sqliteconfig.json` - Database schema definitions
- `PsWebHost_Data/Logs/log.tsv` - Authentication logs

## Future Enhancements

1. **MFA Support** - Re-enable multi-factor authentication flow
2. **Remember Me** - Optional persistent login tokens
3. **Password Reset Flow** - Integration with password reset endpoints
4. **Account Registration Link** - Redirect to registration if user doesn't exist
5. **OAuth Integration** - Support for third-party OAuth providers alongside password auth

## See Also

- Password authentication implementation: `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1:236-285`
- Login lockout logic: `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1:727-815`
- Session management: `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1` (Set-PSWebSession)
