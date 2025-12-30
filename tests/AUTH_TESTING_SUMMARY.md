# Authentication Testing Framework - Summary

## Overview
Complete testing framework for PsWebHost authentication providers with account management utilities and end-to-end flow tests.

## Authentication Providers Supported

### 1. Password Authentication
Standard email/password authentication with PBKDF2 hashing.

### 2. Windows Authentication
Windows domain/local account authentication via LogonUser API.

---

## Account Management Utilities

### Password Provider Utilities

| Script | Purpose | Admin Required |
|--------|---------|----------------|
| `Account_AuthProvider_Password_New.ps1` | Create password user account | No |
| `Account_AuthProvider_Password_Get.ps1` | Query password accounts | No |
| `Account_AuthProvider_Password_Remove.ps1` | Delete password account | No |
| `Account_AuthProvider_Password_RemoveTestingAccounts.ps1` | Bulk cleanup test accounts | No |

**Location:** `system/utility/Account_AuthProvider_Password_*.ps1`

### Windows Provider Utilities

| Script | Purpose | Admin Required |
|--------|---------|----------------|
| `Account_AuthProvider_Windows_New.ps1` | Create local Windows user + DB entry | **Yes** |
| `Account_AuthProvider_Windows_Get.ps1` | Query Windows accounts | No |
| `Account_AuthProvider_Windows_Remove.ps1` | Delete Windows account + local user | **Yes** |
| `Account_AuthProvider_Windows_RemoveTestingAccounts.ps1` | Bulk cleanup Windows test accounts | **Yes** |

**Location:** `system/utility/Account_AuthProvider_Windows_*.ps1`

---

## Test Scripts

### Password Authentication Test
**File:** `tests/Test-PasswordAuthFlow.ps1`

```powershell
# Run with auto-generated test account
.\tests\Test-PasswordAuthFlow.ps1 -UseTestAccount

# Run with specific credentials
.\tests\Test-PasswordAuthFlow.ps1 -Email "user@localhost" -Password "TestPassword12!@"
```

**Test Coverage:**
- ✓ Session cookie creation
- ✓ Auth redirect flow
- ✓ Login page rendering
- ✓ Credential validation
- ✓ Password hash comparison
- ✓ Access token generation
- ✓ Protected resource access
- ✓ Automatic cleanup

### Windows Authentication Test
**File:** `tests/Test-WindowsAuthFlow.ps1`
**Requires:** Administrator privileges

```powershell
# Run with auto-generated test account
.\tests\Test-WindowsAuthFlow.ps1 -UseTestAccount

# Run with specific credentials
.\tests\Test-WindowsAuthFlow.ps1 -UserName "testuser" -Password "TestPass123!@"
```

**Test Coverage:**
- ✓ Local Windows user creation
- ✓ Database user registration
- ✓ Session cookie creation
- ✓ Auth redirect flow
- ✓ Windows LogonUser authentication
- ✓ Access token generation
- ✓ Protected resource access
- ✓ Automatic cleanup (DB + local user)

---

## Test Account Naming Convention

### Password Provider
- **Pattern:** `TA_Password_[5 random letters]`
- **Email:** `TA_Password_xxxxx@localhost`
- **Example:** `TA_Password_mOQYc@localhost`

### Windows Provider
- **Pattern:** `TA_Windows_[5 random letters]`
- **Email:** `TA_Windows_xxxxx@COMPUTERNAME`
- **Example:** `TA_Windows_bntis@W11`

---

## Common Usage Patterns

### Creating Test Accounts

```powershell
# Password test account
$pwdAccount = .\system\utility\Account_AuthProvider_Password_New.ps1 -TestAccount
# Returns: UserID, Email, Password, Created, IsTestAccount

# Windows test account (as Admin)
$winAccount = .\system\utility\Account_AuthProvider_Windows_New.ps1 -TestAccount
# Returns: UserID, Email, UserName, Password, LocalUserSID, Created, IsTestAccount
```

### Listing Accounts

```powershell
# List all password test accounts
.\system\utility\Account_AuthProvider_Password_Get.ps1 -TestAccountsOnly

# List all Windows test accounts with local user status
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -TestAccountsOnly
```

### Cleaning Up Test Accounts

```powershell
# Password - Interactive selection
.\system\utility\Account_AuthProvider_Password_RemoveTestingAccounts.ps1 -SelectWithGridView

# Password - Delete all (no prompt)
.\system\utility\Account_AuthProvider_Password_RemoveTestingAccounts.ps1 -Force

# Windows - Interactive selection (as Admin)
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1 -SelectWithGridView

# Windows - Delete all but keep local users (as Admin)
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1 -Force -KeepLocalUsers
```

---

## Password Requirements

### Password Provider
- Minimum 8 characters
- At least 2 uppercase letters
- At least 2 lowercase letters
- At least 2 numbers
- At least 2 symbols from: `!@#$%^&*()_+-=[]{};':"\\|,.<>/?~`

### Windows Provider
- Follows Windows local account password policy
- Test accounts use same requirements as Password provider for consistency

---

## Key Features

### Automatic Test Account Management
- ✓ Random credential generation
- ✓ Password complexity validation
- ✓ Unique email/username generation
- ✓ Automatic cleanup on test completion
- ✓ Cleanup even on test failure (finally block)

### Comprehensive Error Handling
- ✓ Validation error display (422 status)
- ✓ Authentication failure messages (401 status)
- ✓ HTML-formatted error messages
- ✓ Proper logging to database
- ✓ Lockout tracking and enforcement

### Production-Ready Testing
- ✓ PowerShell Invoke-WebRequest (no browser needed)
- ✓ Session cookie persistence
- ✓ Full redirect chain following
- ✓ HTML content verification
- ✓ Status code assertions

---

## Test Results

### Password Authentication
```
========================================
Password Authentication Flow Test
========================================

[Setup] Creating temporary test account...
      ✓ Test account created
        Email: TA_Password_IKNQM@localhost
        UserID: 258eb8f3-067d-4dcb-8f8d-43d9527edb6c

[1/5] Requesting /spa (should redirect to auth)...
      ✓ Redirected to: /api/v1/auth/getauthtoken?RedirectTo=...
      ✓ Session cookie set: 3b04ffe6-091a-4e37-8355-0f9026f7bde2

[2/5] Loading login page...
      ✓ Login page loaded (Status: 200)

[3/5] Submitting login credentials...
      Response Status: Found
      ✓ Login successful, redirecting to: /api/v1/auth/getaccesstoken...

[4/5] Following redirect to get access token...
      ✓ Access token endpoint responded: 200

[5/5] Accessing protected /spa route...
      ✓ Successfully accessed /spa (Status: 200)
      Content length: 3676 bytes
      ✓ Received HTML content

========================================
✓ Authentication Flow Test Complete
========================================

[Cleanup] Removing test account...
      ✓ Test account removed
```

### Windows Authentication
*Requires Administrator - Run elevated to test*

---

## Files Created

### Utilities
```
system/utility/
├── Account_AuthProvider_Password_New.ps1
├── Account_AuthProvider_Password_Get.ps1
├── Account_AuthProvider_Password_Remove.ps1
├── Account_AuthProvider_Password_RemoveTestingAccounts.ps1
├── Account_AuthProvider_Windows_New.ps1
├── Account_AuthProvider_Windows_Get.ps1
├── Account_AuthProvider_Windows_Remove.ps1
└── Account_AuthProvider_Windows_RemoveTestingAccounts.ps1
```

### Tests
```
tests/
├── Test-PasswordAuthFlow.ps1
├── Test-WindowsAuthFlow.ps1
├── AUTH_TESTING_SUMMARY.md (this file)
└── WINDOWS_AUTH_UTILITIES.md
```

### Additional Test Utilities
```
tests/
├── Create-PasswordUser.ps1 (original manual test)
├── Fix-LoginAttemptData.ps1 (database cleanup)
└── PASSWORD_AUTH_FIXES.md (implementation notes)
```

---

## Integration with CI/CD

These scripts can be integrated into automated testing pipelines:

```powershell
# CI/CD Pipeline Example
try {
    # Run password auth test (no admin needed)
    $result = .\tests\Test-PasswordAuthFlow.ps1 -UseTestAccount
    if ($LASTEXITCODE -ne 0) { throw "Password auth test failed" }

    # Run Windows auth test (if running on Windows with admin)
    if ($IsWindows -and $IsAdmin) {
        $result = .\tests\Test-WindowsAuthFlow.ps1 -UseTestAccount
        if ($LASTEXITCODE -ne 0) { throw "Windows auth test failed" }
    }

    # Cleanup any orphaned test accounts
    .\system\utility\Account_AuthProvider_Password_RemoveTestingAccounts.ps1 -Force

    Write-Host "✓ All authentication tests passed" -ForegroundColor Green
}
catch {
    Write-Host "✗ Authentication tests failed: $_" -ForegroundColor Red
    exit 1
}
```

---

## Next Steps

1. **Run Tests:** Execute both authentication flow tests
2. **Verify Cleanup:** Ensure no test accounts remain
3. **Monitor Logs:** Check `PsWebHost_Data/Logs/log.tsv` for issues
4. **Add More Providers:** Extend framework for OAuth, SAML, etc.

---

## Troubleshooting

### Test Account Accumulation
If test accounts accumulate due to interrupted tests:
```powershell
# List all test accounts
.\system\utility\Account_AuthProvider_Password_Get.ps1 -TestAccountsOnly
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -TestAccountsOnly

# Clean up interactively
.\system\utility\Account_AuthProvider_Password_RemoveTestingAccounts.ps1 -SelectWithGridView
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1 -SelectWithGridView
```

### Database Lockout Issues
If IPs get locked out during testing:
```powershell
# Check lockout status
Get-LastLoginAttempt -IPAddress "127.0.0.1"

# Reset if needed (requires WebHost environment)
.\tests\Fix-LoginAttemptData.ps1
```

### Permission Errors (Windows)
Ensure PowerShell is running as Administrator for Windows provider operations.
