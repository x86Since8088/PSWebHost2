# Windows Authentication Utilities

## Overview
Complete set of utilities for managing Windows-authenticated user accounts in PsWebHost.

## Account Management Scripts

### 1. Account_AuthProvider_Windows_New.ps1
**Requires Administrator**

Creates a new Windows-authenticated user account (both local Windows user and database entry).

```powershell
# Create test account (auto-generates credentials)
.\system\utility\Account_AuthProvider_Windows_New.ps1 -TestAccount

# Create specific account
.\system\utility\Account_AuthProvider_Windows_New.ps1 -UserName "john.doe" -Password "SecurePass123!@" -Email "john.doe@W11"
```

**Features:**
- Creates local Windows user with `New-LocalUser`
- Registers user in database with Windows provider
- Test account prefix: `TA_Windows_[5 random letters]`
- Auto-generates compliant passwords for test accounts
- Rollback support: removes local user if database creation fails
- Returns account object with credentials

### 2. Account_AuthProvider_Windows_Get.ps1

Retrieves Windows-authenticated user accounts from database.

```powershell
# Get by email
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -Email "user@W11"

# Get by UserID
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -UserID "d2e7a626-..."

# Get by Windows UserName
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -UserName "TA_Windows_mOQYc"

# List all Windows accounts
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -ListAll

# List only test accounts
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -TestAccountsOnly
```

**Features:**
- Joins database and local Windows user information
- Shows if local Windows user still exists
- Displays local user SID and enabled status
- Converts Unix timestamps to readable dates

### 3. Account_AuthProvider_Windows_Remove.ps1
**Requires Administrator**

Removes a Windows-authenticated user account.

```powershell
# Remove account (prompts for confirmation)
.\system\utility\Account_AuthProvider_Windows_Remove.ps1 -ID "987f1461-..."

# Remove without confirmation
.\system\utility\Account_AuthProvider_Windows_Remove.ps1 -ID "987f1461-..." -Force

# Remove database entry but keep local Windows user
.\system\utility\Account_AuthProvider_Windows_Remove.ps1 -ID "987f1461-..." -KeepLocalUser
```

**Features:**
- Removes from `auth_user_provider` and `Users` tables
- Cleans up `LoginSessions` entries
- Removes local Windows user with `Remove-LocalUser`
- Option to keep local user for troubleshooting
- WhatIf and Confirm support

### 4. Account_AuthProvider_Windows_RemoveTestingAccounts.ps1
**Requires Administrator**

Bulk removal of test accounts.

```powershell
# List test accounts (no deletion)
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1

# Delete all test accounts with confirmation
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1 -Force

# Interactive selection with GridView
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1 -SelectWithGridView

# Remove database entries but keep local Windows users
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1 -Force -KeepLocalUsers
```

**Features:**
- Finds all accounts with `UserName` like `TA_Windows_%`
- Interactive selection via `Out-GridView`
- Batch deletion with progress
- Summary report (deleted/failed counts)

## Testing

### Test-WindowsAuthFlow.ps1
**Requires Administrator**

Comprehensive end-to-end test of Windows authentication flow.

```powershell
# Run with temporary test account (recommended)
.\tests\Test-WindowsAuthFlow.ps1 -UseTestAccount

# Run with specific credentials
.\tests\Test-WindowsAuthFlow.ps1 -UserName "testuser" -Password "TestPass123!@"
```

**Test Steps:**
1. Creates test account (local Windows user + database entry)
2. Requests /spa → verifies redirect to auth
3. Loads Windows login page
4. Submits Windows credentials
5. Follows redirect to get access token
6. Accesses protected /spa route
7. Cleans up test account (database + local user)

**Success Criteria:**
- ✓ Test account created
- ✓ Session cookie set
- ✓ Login page loaded (200)
- ✓ Authentication successful (302 redirect)
- ✓ Access token retrieved (200)
- ✓ Protected resource accessible (200)
- ✓ HTML content delivered
- ✓ Test account removed

## Administrator Requirements

The following operations **require Administrator privileges**:
- Creating local Windows users (`New-LocalUser`)
- Removing local Windows users (`Remove-LocalUser`)

Operations that **do not** require Administrator:
- Querying database for Windows accounts
- Listing local users (read-only)

## Test Account Naming Convention

All test accounts follow this pattern:
- **UserName:** `TA_Windows_[5 random letters]`
- **Email:** `TA_Windows_[5 random letters]@COMPUTERNAME`
- **Example:** `TA_Windows_mOQYc@W11`

This makes it easy to identify and clean up test accounts.

## Security Notes

1. **Password Complexity:** Generated passwords meet Windows requirements:
   - Minimum 8 characters
   - Contains uppercase, lowercase, numbers, and symbols

2. **Local User Settings:**
   - `PasswordNeverExpires` is set to prevent test failures
   - Description set to "Test account for PsWebHost Windows authentication"

3. **Cleanup:** Always clean up test accounts to avoid:
   - Accumulating unused local Windows users
   - Database bloat
   - Security concerns

## Troubleshooting

### "This test must be run as Administrator"
Run PowerShell as Administrator or use:
```powershell
Start-Process pwsh -Verb RunAs
```

### "Local Windows user already exists"
A previous test may have failed during cleanup. Remove manually:
```powershell
Remove-LocalUser -Name "TA_Windows_xxxxx"
```

### "Database user exists but local user doesn't"
Use `-KeepLocalUser` when removing to investigate database state:
```powershell
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -TestAccountsOnly
```

## Comparison with Password Provider

| Feature | Windows Provider | Password Provider |
|---------|-----------------|-------------------|
| Local User Required | ✓ Yes | ✗ No |
| Administrator Rights | ✓ Yes | ✗ No |
| Password Storage | Windows SAM | Database (PBKDF2) |
| Authentication Method | Windows LogonUser | Hash comparison |
| Cleanup Complexity | Higher (2 systems) | Lower (database only) |

## Files Created

```
system/utility/
├── Account_AuthProvider_Windows_New.ps1
├── Account_AuthProvider_Windows_Get.ps1
├── Account_AuthProvider_Windows_Remove.ps1
└── Account_AuthProvider_Windows_RemoveTestingAccounts.ps1

tests/
├── Test-WindowsAuthFlow.ps1
└── WINDOWS_AUTH_UTILITIES.md (this file)
```
