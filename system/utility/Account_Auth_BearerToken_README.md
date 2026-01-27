# Bearer Token (API Key) Management Utilities

These utilities manage bearer tokens (API keys) for authentication with PSWebHost APIs.

## Overview

Bearer tokens are API keys stored in the `API_Keys` database table. They are linked to user accounts and inherit the user's roles and permissions.

## Scripts

### Account_Auth_BearerToken_Get.ps1

Creates new bearer tokens or lists existing ones.

**List all tokens:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -ListAll
```

**List only test tokens:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -TestTokensOnly
```

**List tokens for a specific user:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -UserID "user-guid-here"
```

**Create a test token with debug role:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -Create -TestToken -Roles @('debug')
```

**Create a test token with multiple roles:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -Create -TestToken -Roles @('debug', 'admin', 'authenticated')
```

**Create a test token with groups:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -Create -TestToken -Roles @('debug') -Groups @('developers')
```

**Create a token for an existing user:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -Create -ExistingUserID "user-guid" -Name "MyAPIKey"
```

**Create a token with IP restrictions:**
```powershell
.\Account_Auth_BearerToken_Get.ps1 -Create -TestToken -Roles @('debug') -AllowedIPs @('192.168.1.100', '10.0.0.5')
```

**Create a token with expiration:**
```powershell
$expires = (Get-Date).AddDays(30)
.\Account_Auth_BearerToken_Get.ps1 -Create -TestToken -Roles @('debug') -ExpiresAt $expires
```

### Account_Auth_BearerToken_Remove.ps1

Removes a bearer token.

**Remove by KeyID:**
```powershell
.\Account_Auth_BearerToken_Remove.ps1 -KeyID "key-guid-here"
```

**Remove by Name:**
```powershell
.\Account_Auth_BearerToken_Remove.ps1 -Name "TA_Token_AbCdE"
```

**Remove without confirmation:**
```powershell
.\Account_Auth_BearerToken_Remove.ps1 -KeyID "key-guid" -Force
```

**Remove token and associated test user:**
```powershell
.\Account_Auth_BearerToken_Remove.ps1 -KeyID "key-guid" -RemoveUser -Force
```

### Account_Auth_BearerToken_RemoveTestingTokens.ps1

Batch removes test tokens (tokens with names starting with `TA_Token_`).

**List test tokens (no deletion):**
```powershell
.\Account_Auth_BearerToken_RemoveTestingTokens.ps1
```

**Delete all test tokens:**
```powershell
.\Account_Auth_BearerToken_RemoveTestingTokens.ps1 -Force
```

**Select tokens interactively:**
```powershell
.\Account_Auth_BearerToken_RemoveTestingTokens.ps1 -SelectWithGridView
```

**Delete test tokens and their associated users:**
```powershell
.\Account_Auth_BearerToken_RemoveTestingTokens.ps1 -Force -RemoveUsers
```

### Account_New_TestUser.ps1 (Primitive)

Reusable script for creating test users with roles and groups. Used internally by bearer token creation.

**Create a test user with roles:**
```powershell
.\Account_New_TestUser.ps1 -Roles @('debug', 'admin') -Prefix "TestUser"
```

**Create a test user with groups:**
```powershell
.\Account_New_TestUser.ps1 -Roles @('developer') -Groups @('team-alpha') -Prefix "DevUser"
```

## Usage Examples

### Example 1: Create a Debug Token for Testing CLI API

```powershell
# Create a test token with debug role
$token = .\Account_Auth_BearerToken_Get.ps1 -Create -TestToken -Roles @('debug') -Verbose

# Use the token
$headers = @{ 'Authorization' = "Bearer $($token.BearerToken)" }
$body = @{ script = 'Get-Date | ConvertTo-Json' } | ConvertTo-Json
Invoke-WebRequest -Uri 'http://localhost:8080/api/v1/cli' -Method POST -Headers $headers -Body $body -ContentType 'application/json'
```

### Example 2: Create a Token for Production API Access

```powershell
# Create a token for existing production user
$token = .\Account_Auth_BearerToken_Get.ps1 -Create `
    -ExistingUserID "prod-user-guid" `
    -Name "ProductionAPIKey_2026" `
    -AllowedIPs @('203.0.113.0') `
    -ExpiresAt (Get-Date).AddMonths(6) `
    -Description "Production API access for automated system"

# Save token securely
$token.BearerToken | Out-File "secure-token.txt"
```

### Example 3: Audit and Clean Up Test Tokens

```powershell
# List all test tokens
$testTokens = .\Account_Auth_BearerToken_Get.ps1 -TestTokensOnly
$testTokens | Format-Table Name, UserEmail, CreatedAt, LastUsed

# Remove unused test tokens (interactive selection)
.\Account_Auth_BearerToken_RemoveTestingTokens.ps1 -SelectWithGridView

# Or remove all test tokens older than 7 days
$testTokens | Where-Object {
    (Get-Date) - [datetime]$_.CreatedAt -gt [TimeSpan]::FromDays(7)
} | ForEach-Object {
    .\Account_Auth_BearerToken_Remove.ps1 -KeyID $_.KeyID -Force
}
```

### Example 4: Create Tokens for Different Permission Levels

```powershell
# Read-only token
$readToken = .\Account_Auth_BearerToken_Get.ps1 -Create -TestToken `
    -Roles @('authenticated', 'viewer') `
    -Name "ReadOnly_Token"

# Admin token
$adminToken = .\Account_Auth_BearerToken_Get.ps1 -Create -TestToken `
    -Roles @('authenticated', 'admin', 'debug') `
    -Name "Admin_Token"

# Service account token
$serviceToken = .\Account_Auth_BearerToken_Get.ps1 -Create -TestToken `
    -Roles @('service', 'api-access') `
    -Name "ServiceAccount_Token" `
    -Description "Automated monitoring service"
```

## Security Considerations

1. **Token Storage**: Bearer tokens are only displayed ONCE when created. Store them securely.

2. **Token Hashing**: Tokens are hashed (SHA256) before storage in the database. The plaintext token never exists in the database.

3. **IP Restrictions**: Use `-AllowedIPs` to restrict token usage to specific IP addresses.

4. **Expiration**: Use `-ExpiresAt` to create time-limited tokens.

5. **Test Tokens**: All test tokens created with `-TestToken` are prefixed with `TA_Token_` or `TA_TokenUser_` for easy identification and cleanup.

6. **Roles and Permissions**: Tokens inherit all roles and permissions from their associated user account.

## Database Schema

Bearer tokens are stored in the `API_Keys` table:

```sql
CREATE TABLE API_Keys (
    KeyID TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    KeyHash TEXT NOT NULL,
    UserID TEXT NOT NULL,
    AllowedIPs TEXT,
    CreatedBy TEXT,
    CreatedAt TEXT,
    ExpiresAt TEXT,
    LastUsed TEXT,
    Enabled INTEGER DEFAULT 1,
    Description TEXT,
    FOREIGN KEY (UserID) REFERENCES Users(UserID)
);
```

## Related Scripts

- `Account_AuthProvider_Password_*.ps1` - Password user management
- `Account_New_TestUser.ps1` - Primitive for creating test users with roles/groups

## Troubleshooting

**Error: "User not found"**
- Ensure the UserID exists when using `-ExistingUserID`

**Error: "Token not found"**
- Verify the KeyID or Name when removing tokens
- Use `-ListAll` to see all available tokens

**Error: "Failed to create API key"**
- Check that the user account exists and is valid
- Verify database permissions

**Token not working in API calls:**
- Ensure you're using the correct format: `Authorization: Bearer <token>`
- Check if token has expired
- Verify the user has required roles for the endpoint
- Check IP restrictions if `AllowedIPs` is set

## Notes

- Test tokens (prefix `TA_Token_` or `TA_TokenUser_`) should only be used in development/testing
- Production tokens should use meaningful names and proper expiration dates
- Regularly audit and rotate API keys
- Use IP restrictions for production tokens
- Monitor `LastUsed` field to identify unused tokens
