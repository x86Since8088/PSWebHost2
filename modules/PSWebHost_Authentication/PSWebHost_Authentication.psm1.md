# PSWebHost_Authentication.psm1

PowerShell authentication and user management module for PSWebHost. Provides comprehensive authentication, authorization, security validation, session management, and user/group/role administration.

## Module Overview

This module implements:
- Multi-method authentication (Password, Windows)
- User account management with password hashing (PBKDF2)
- Role-based access control (RBAC) with group inheritance
- Login attempt tracking and lockout protection
- Session management with database persistence
- Input validation and security scanning
- Card settings and session management

## Core Authentication Functions

### Get-AuthenticationMethod

Returns available authentication methods.

```powershell
Get-AuthenticationMethod [-Verbose]
```

**Returns:** Array of authentication method names (`@("Password", "OTP_Email", "OTP_SMS")`)

### Get-AuthenticationMethodForm

Returns form field definitions for a specific authentication method.

```powershell
Get-AuthenticationMethodForm -Name <string> [-Verbose]
```

**Parameters:**
- `-Name`: Authentication method name (e.g., "Password", "OTP_Email", "OTP_SMS")

**Returns:** Hashtable containing form field specifications (type, required)

**Example:**
```powershell
$form = Get-AuthenticationMethodForm -Name "Password"
# Returns: @{ Username = @{ type="text"; required=$true }; Password = @{ type="password"; required=$true }}
```

### Invoke-AuthenticationMethod

Authenticates user credentials against the specified authentication provider.

```powershell
Invoke-AuthenticationMethod -Name <string> -FormData <hashtable> [-Verbose]
```

**Parameters:**
- `-Name`: Authentication method ("Password" or "Windows")
- `-FormData`: Hashtable with authentication data

**Returns:** `$true` if authentication succeeds, `$false` otherwise

**Supported Methods:**

**Password Authentication:**
- Retrieves user from database by email
- Compares PBKDF2 hash of provided password with stored hash
- Uses salt from database for hash generation

**Windows Authentication:**
- Delegates to `system/auth/Test-PSWebWindowsAuth.ps1`
- Validates credentials against LocalMachine context

**Example:**
```powershell
$result = Invoke-AuthenticationMethod -Name "Password" -FormData @{ Username="user@domain.com"; Password="pass123" }
```

### PSWebLogon

Records login attempts and enforces lockout policies.

```powershell
PSWebLogon -ProviderName <string> -Result <string> -Request <HttpListenerRequest> [-UserID <string>] [-Verbose]
```

**Parameters:**
- `-ProviderName`: Authentication provider used
- `-Result`: "Success", "Fail", or "Error"
- `-Request`: HttpListenerRequest object
- `-UserID`: User identifier (defaults to "anonymous")

**Behavior:**
- **On Success:** Resets violation counts, creates login session, logs success
- **On Failure:** Increments violation counts, applies lockouts:
  - Default: 4.5 second cooldown
  - Every 5 user failures: 1 minute lockout
  - After 10 IP failures: 1 hour IP lockout

**Example:**
```powershell
PSWebLogon -ProviderName "Password" -Result "Success" -Request $Request -UserID $user.UserID
```

### Test-LoginLockout

Checks if IP address or username is currently locked out.

```powershell
Test-LoginLockout -IPAddress <string> -Username <string> [-Verbose]
```

**Parameters:**
- `-IPAddress`: Client IP address
- `-Username`: Username attempting login

**Returns:** PSCustomObject with properties:
- `LockedOut`: Boolean
- `LockedUntil`: DateTime (if locked)
- `Message`: Lockout message (if locked)

**Example:**
```powershell
$lockout = Test-LoginLockout -IPAddress "192.168.1.100" -Username "user@domain.com"
if ($lockout.LockedOut) { return $lockout.Message }
```

## User Management Functions

### Get-PSWebHostUser

Retrieves user information from database.

```powershell
Get-PSWebHostUser -Email <string> [-Verbose]
Get-PSWebHostUser -UserID <string> [-Verbose]
Get-PSWebHostUser -Listall [-Verbose]
```

**Parameters:**
- `-Email`: User email address
- `-UserID`: User GUID
- `-Listall`: Returns all users

**Returns:** User object(s) with properties: UserID, Email, PasswordHash

**Example:**
```powershell
$user = Get-PSWebHostUser -Email "test@domain.com"
```

### Get-PSWebHostUsers

Returns array of all user email addresses.

```powershell
Get-PSWebHostUsers [-Verbose]
```

**Returns:** Array of email strings

### Get-UserAuthenticationMethods

Gets enabled authentication providers for a user.

```powershell
Get-UserAuthenticationMethods -Email <string> [-Verbose]
```

**Parameters:**
- `-Email`: User email address

**Returns:** Array of provider names (e.g., `@("Password", "Windows")`)

**Example:**
```powershell
$methods = Get-UserAuthenticationMethods -Email "user@domain.com"
```

### Register-PSWebHostUser

Creates new user account with authentication provider.

```powershell
Register-PSWebHostUser -UserName <string> -Provider <string> [-Email <string>] [-Phone <string>]
                        [-Password <string>] [-ProviderData <hashtable>] [-Verbose]
```

**Parameters:**
- `-UserName`: Username (required)
- `-Provider`: Authentication provider (required, e.g., "Password", "Windows")
- `-Email`: Email address
- `-Phone`: Phone number
- `-Password`: Password (for Password provider)
- `-ProviderData`: Additional provider-specific data

**Behavior:**
- Generates new GUID for UserID
- For Password provider: Creates salt, hashes password with PBKDF2 (10000 iterations, 160-bit hash)
- Stores user in `Users` table
- Stores provider data in `auth_user_provider` table (JSON-encoded)

**Returns:** User object

**Example:**
```powershell
$user = Register-PSWebHostUser -UserName "john@domain.com" -Email "john@domain.com" -Provider "Password" -Password "SecureP@ss123"
```

### New-PSWebHostUser

Convenience wrapper for creating Password-authenticated users.

```powershell
New-PSWebHostUser -Email <string> [-UserName <string>] [-Password <string>] [-Phone <string>] [-Verbose]
```

**Parameters:**
- `-Email`: Email address (required)
- `-UserName`: Username (defaults to Email)
- `-Password`: Password (auto-generated if not provided)
- `-Phone`: Phone number

**Returns:** User object

**Example:**
```powershell
$user = New-PSWebHostUser -Email "user@domain.com" -Password "MyP@ssw0rd"
```

## Role and Permission Functions

### Get-PSWebHostRole

Retrieves roles from database.

```powershell
Get-PSWebHostRole -UserID <string> [-Verbose]
Get-PSWebHostRole -ListAll [-Verbose]
```

**Parameters:**
- `-UserID`: User GUID (returns roles for user + group-inherited roles)
- `-ListAll`: Returns all distinct role names

**Returns:**
- For UserID: Array of role names (includes direct + group-inherited)
- For ListAll: Array of all role names

**Example:**
```powershell
$roles = Get-PSWebHostRole -UserID $user.UserID
```

### Add-PSWebHostRole

Creates a new role in the system.

```powershell
Add-PSWebHostRole -RoleName <string> [-Verbose]
```

**Parameters:**
- `-RoleName`: Name of role to create

**Example:**
```powershell
Add-PSWebHostRole -RoleName "Administrator"
```

### Remove-PSWebHostRole

Deletes a role from the system.

```powershell
Remove-PSWebHostRole -RoleName <string> [-Verbose]
```

**Parameters:**
- `-RoleName`: Name of role to remove

### Add-PSWebHostRoleAssignment

Assigns a role to a user.

```powershell
Add-PSWebHostRoleAssignment -UserID <string> -RoleName <string> [-Verbose]
```

**Parameters:**
- `-UserID`: User GUID
- `-RoleName`: Role name

**Example:**
```powershell
Add-PSWebHostRoleAssignment -UserID $user.UserID -RoleName "Administrator"
```

### Remove-PSWebHostRoleAssignment

Removes role assignment from user.

```powershell
Remove-PSWebHostRoleAssignment -UserID <string> -RoleName <string> [-Verbose]
```

## Group Management Functions

### Get-PSWebHostGroup

Retrieves group information by name.

```powershell
Get-PSWebHostGroup -Name <string> [-Verbose]
```

**Parameters:**
- `-Name`: Group name

**Returns:** Group object with properties: GroupID, Name, Created, Updated

### Add-PSWebHostGroup

Creates a new user group.

```powershell
Add-PSWebHostGroup -GroupName <string> [-Verbose]
```

**Parameters:**
- `-GroupName`: Name of group to create

**Behavior:**
- Generates new GUID for GroupID
- Sets Created and Updated timestamps

**Example:**
```powershell
Add-PSWebHostGroup -GroupName "Developers"
```

### Remove-PSWebHostGroup

Deletes a group from the system.

```powershell
Remove-PSWebHostGroup -GroupID <string> [-Verbose]
```

**Parameters:**
- `-GroupID`: Group GUID

### Add-PSWebHostGroupMember

Adds a user to a group.

```powershell
Add-PSWebHostGroupMember -UserID <string> -GroupID <string> [-Verbose]
```

**Parameters:**
- `-UserID`: User GUID
- `-GroupID`: Group GUID

**Example:**
```powershell
$group = Get-PSWebHostGroup -Name "Developers"
Add-PSWebHostGroupMember -UserID $user.UserID -GroupID $group.GroupID
```

### Remove-PSWebHostGroupMember

Removes user from group.

```powershell
Remove-PSWebHostGroupMember -UserID <string> -GroupID <string> [-Verbose]
```

## Session Management Functions

### Get-LoginSession

Retrieves login session from database.

```powershell
Get-LoginSession -SessionID <string> [-Verbose]
```

**Parameters:**
- `-SessionID`: Session GUID

**Returns:** Session object or `$null`

### Set-LoginSession

Creates or updates login session in database.

```powershell
Set-LoginSession -SessionID <string> -UserID <string> -Provider <string>
                 [-AuthenticationTime <datetime>] [-AuthenticationState <string>]
                 -LogonExpires <datetime> -UserAgent <string> [-Verbose]
```

**Parameters:**
- `-SessionID`: Session GUID
- `-UserID`: User GUID
- `-Provider`: Authentication provider used
- `-AuthenticationTime`: When authenticated (defaults to current time)
- `-AuthenticationState`: State string (defaults to "completed" if UserID provided)
- `-LogonExpires`: Session expiration time
- `-UserAgent`: User-Agent string from request

**Behavior:**
- Inserts new session or updates existing
- Stores all timestamps as Unix epoch seconds

**Example:**
```powershell
Set-LoginSession -SessionID $sessionID -UserID $user.UserID -Provider "Password" `
                 -LogonExpires (Get-Date).AddHours(8) -UserAgent $Request.UserAgent
```

### Remove-LoginSession

Deletes session from database.

```powershell
Remove-LoginSession -SessionID <string> [-Verbose]
```

**Parameters:**
- `-SessionID`: Session GUID to delete

### Get-LastLoginAttempt

Retrieves last login attempt data for an IP address.

```powershell
Get-LastLoginAttempt -IPAddress <string> [-Verbose]
```

**Parameters:**
- `-IPAddress`: IP address

**Returns:** Login attempt object with violation counts and lockout times

### Set-LastLoginAttempt

Records login attempt with lockout data.

```powershell
Set-LastLoginAttempt -IPAddress <string> -Username <string> -Time <datetime>
                     [-UserNameLockedUntil <datetime>] [-IPAddressLockedUntil <datetime>]
                     -UserViolationsCount <int> -IPViolationCount <int> [-Verbose]
```

**Parameters:**
- `-IPAddress`: Client IP
- `-Username`: Username attempted
- `-Time`: Attempt timestamp
- `-UserNameLockedUntil`: User lockout expiration (nullable)
- `-IPAddressLockedUntil`: IP lockout expiration (nullable)
- `-UserViolationsCount`: Count of user violations
- `-IPViolationCount`: Count of IP violations

## Security Validation Functions

### Test-IsValidEmailAddress

Validates email address format and scans for high-risk Unicode.

```powershell
Test-IsValidEmailAddress -Email <string> [-Regex <string>] [-AddCustomRegex <string>] [-Verbose]
```

**Parameters:**
- `-Email`: Email to validate
- `-Regex`: Custom validation regex (default: `'^[a-zA-Z0-9._+-]+@[a-zA-Z0-9\.-]+'`)
- `-AddCustomRegex`: Additional regex pattern to OR with default

**Returns:** Hashtable:
- `isValid`: Boolean
- `Message`: Validation message
- `Findings`: Hashtable of high-risk characters (if found)

**Example:**
```powershell
$result = Test-IsValidEmailAddress -Email "user@domain.com"
if (-not $result.isValid) { Write-Error $result.Message }
```

### Test-StringForHighRiskUnicode

Scans string for dangerous Unicode characters.

```powershell
Test-StringForHighRiskUnicode -String <string> [-Verbose]
```

**Parameters:**
- `-String`: String to validate

**Returns:** Hashtable:
- `IsValid`: Boolean
- `Message`: Validation message or detailed findings
- `Findings`: Hashtable mapping character codes to risk details (if found)

**Detected Threats:**
- C0/C1 Control Characters (Risk 8-10): NUL, CR, LF, ESC, etc.
- Invisible Characters (Risk 5-9): ZWSP, ZWNJ, ZWJ, BOM
- Bidirectional Overrides (Risk 9): LRM, RLM, LRE, RLE, RLO (Bidi attacks)
- Line/Paragraph Separators (Risk 7): LS, PS
- Whitespace Variants (Risk 6): SHY, NNBSP, MMSP, IDSP

**Example:**
```powershell
$result = Test-StringForHighRiskUnicode -String $userInput
if (-not $result.IsValid) {
    Write-Warning "High-risk characters detected: $($result.Message)"
}
```

### Test-IsValidPassword

Validates password complexity requirements.

```powershell
Test-IsValidPassword -Password <string> [-Length <int>] [-Uppercase <int>] [-LowerCase <int>]
                     [-Symbols <int>] [-Numbers <int>] [-ValidSymbolCharactersRegex <string>] [-Verbose]
```

**Parameters:**
- `-Password`: Password to validate
- `-Length`: Minimum length (default: 8)
- `-Uppercase`: Minimum uppercase characters (default: 2)
- `-LowerCase`: Minimum lowercase characters (default: 2)
- `-Symbols`: Minimum symbol characters (default: 2)
- `-Numbers`: Minimum numeric characters (default: 2)
- `-ValidSymbolCharactersRegex`: Allowed symbols (default: `'[!@#$%^&*()_+\-=\[\]{};'':"\\|,.<>/?``~]'`)

**Returns:** Hashtable:
- `IsValid`: Boolean
- `Message`: Validation message

**Validation Steps:**
1. Length check (minimum 8)
2. Uppercase count
3. Lowercase count
4. Number count
5. Symbol count
6. Unapproved character check
7. High-risk Unicode scan

**Example:**
```powershell
$result = Test-IsValidPassword -Password "P@ssw0rd123"
if ($result.IsValid) { Write-Host "Password is valid" }
```

### Protect-String

Encrypts string using Windows DPAPI (user+machine context).

```powershell
Protect-String -PlainText <string> [-Verbose]
```

**Parameters:**
- `-PlainText`: String to encrypt

**Returns:** Encrypted string (tied to current user and machine)

**Example:**
```powershell
$encrypted = Protect-String -PlainText "SensitiveData"
```

### Unprotect-String

Decrypts string encrypted by Protect-String.

```powershell
Unprotect-String -EncryptedString <string> [-Verbose]
```

**Parameters:**
- `-EncryptedString`: Encrypted string to decrypt

**Returns:** Decrypted plain text

**Example:**
```powershell
$plainText = Unprotect-String -EncryptedString $encrypted
```

## Card Settings Functions

### Get-CardSettings

Retrieves card settings JSON for user and endpoint.

```powershell
Get-CardSettings -EndpointGuid <string> -UserId <string> [-Verbose]
```

**Parameters:**
- `-EndpointGuid`: Endpoint GUID
- `-UserId`: User ID

**Returns:** JSON settings string from `card_settings.data` column

### Set-CardSession

Stores card session information.

```powershell
Set-CardSession -SessionID <string> -UserID <string> -CardGUID <string>
                -DataBackend <string> [-CardDefinition <string>] [-Verbose]
```

**Parameters:**
- `-SessionID`: Session GUID
- `-UserID`: User GUID
- `-CardGUID`: Card GUID
- `-DataBackend`: Data backend identifier
- `-CardDefinition`: Optional card definition data

**Behavior:** Inserts or replaces card session in `CardSessions` table

## Implementation Details

### Password Hashing

Uses PBKDF2 (RFC 2898) with:
- 16-byte random salt
- 10,000 iterations
- 160-bit (20-byte) hash output
- Base64 encoding for storage

**Storage Format (auth_user_provider.data):**
```json
{
  "Password": "base64-encoded-hash",
  "Salt": "base64-encoded-salt"
}
```

### Database Tables Used

- `Users`: UserID, Email, PasswordHash
- `auth_user_provider`: UserID, UserName, provider, data (JSON), created, locked_out, enabled
- `PSWeb_Roles`: PrincipalID, PrincipalType ("User"/"Group"), RoleName
- `User_Groups`: GroupID, Name, Created, Updated
- `User_Groups_Map`: UserID, GroupID
- `LoginSessions`: SessionID, UserID, Provider, AuthenticationTime, AuthenticationState, LogonExpires, UserAgent
- `LastLoginAttempt`: IPAddress, Username, Time, UserNameLockedUntil, IPAddressLockedUntil, UserViolationsCount, IPViolationCount
- `card_settings`: user_id, endpoint_guid, data (JSON)
- `CardSessions`: SessionID, UserID, CardGUID, DataBackend, CardDefinition

### SQL Injection Protection

All functions use `Sanitize-SqlQueryString` (from PSWebHost_Support) to escape SQL parameters before query construction.

### Logging

All significant operations log to PSWebHost logging system via `Write-PSWebHostLog` with:
- Severity levels: Info, Warning, Error, Critical
- Categories: Auth, RoleManagement, GroupManagement, CardSession, etc.
- Structured data payloads

## Security Considerations

1. **Password Security**: PBKDF2 with 10,000 iterations provides strong protection against brute-force attacks
2. **Lockout Protection**: Escalating lockouts prevent credential stuffing and brute-force attacks
3. **Unicode Validation**: Prevents homograph attacks, Bidi spoofing, and injection via control characters
4. **SQL Injection**: All inputs sanitized before database operations
5. **Session Security**: Sessions stored in database with expiration tracking
6. **DPAPI Encryption**: Protect-String/Unprotect-String tied to user+machine context

## Dependencies

Requires PSWebHost modules:
- **PSWebHost_Database**: SQLite operations (Get-PSWebSQLiteData, Invoke-PSWebSQLiteNonQuery, New-PSWebSQLiteData)
- **PSWebHost_Support**: Logging (Write-PSWebHostLog) and sanitization (Sanitize-SqlQueryString)

External script dependency:
- `system/auth/Test-PSWebWindowsAuth.ps1`: Windows authentication validation

## Version History

Last Updated: 2025-12-29

Major changes since last documentation:
- Added comprehensive group management functions
- Added role assignment and retrieval with group inheritance
- Enhanced session management with database persistence
- Added card settings and card session management
- Improved lockout tracking with separate user/IP violation counts
- Added high-risk Unicode detection with detailed threat categorization
- Enhanced logging throughout all functions
- Standardized error handling and parameter validation
