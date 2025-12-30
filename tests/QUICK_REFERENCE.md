# Authentication Testing - Quick Reference

## Run Tests

### Password Authentication
```powershell
.\tests\Test-PasswordAuthFlow.ps1 -UseTestAccount
```
✓ No admin required
✓ Auto-creates and cleans up test account
✓ Tests complete auth flow

### Windows Authentication
```powershell
# Must run as Administrator
.\tests\Test-WindowsAuthFlow.ps1 -UseTestAccount
```
⚠️ **Requires Administrator**
✓ Creates local Windows user
✓ Auto-cleanup of DB + local user

---

## Account Management

### Create Accounts

```powershell
# Password account
.\system\utility\Account_AuthProvider_Password_New.ps1 -TestAccount

# Windows account (as Admin)
.\system\utility\Account_AuthProvider_Windows_New.ps1 -TestAccount
```

### List Accounts

```powershell
# List password test accounts
.\system\utility\Account_AuthProvider_Password_Get.ps1 -TestAccountsOnly

# List Windows test accounts
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -TestAccountsOnly
```

### Cleanup Test Accounts

```powershell
# Password - Interactive
.\system\utility\Account_AuthProvider_Password_RemoveTestingAccounts.ps1 -SelectWithGridView

# Windows - Force delete all (as Admin)
.\system\utility\Account_AuthProvider_Windows_RemoveTestingAccounts.ps1 -Force
```

---

## Files Created

### 8 Account Management Utilities
- `Account_AuthProvider_Password_New.ps1`
- `Account_AuthProvider_Password_Get.ps1`
- `Account_AuthProvider_Password_Remove.ps1`
- `Account_AuthProvider_Password_RemoveTestingAccounts.ps1`
- `Account_AuthProvider_Windows_New.ps1` *(admin)*
- `Account_AuthProvider_Windows_Get.ps1`
- `Account_AuthProvider_Windows_Remove.ps1` *(admin)*
- `Account_AuthProvider_Windows_RemoveTestingAccounts.ps1` *(admin)*

### 2 Comprehensive Tests
- `Test-PasswordAuthFlow.ps1`
- `Test-WindowsAuthFlow.ps1` *(admin)*

### 3 Documentation Files
- `AUTH_TESTING_SUMMARY.md`
- `WINDOWS_AUTH_UTILITIES.md`
- `QUICK_REFERENCE.md` *(this file)*

---

## Test Account Pattern

| Provider | Username Pattern | Email Pattern |
|----------|-----------------|---------------|
| Password | `TA_Password_xxxxx` | `TA_Password_xxxxx@localhost` |
| Windows | `TA_Windows_xxxxx` | `TA_Windows_xxxxx@COMPUTERNAME` |

*xxxxx = 5 random letters*

---

## Status: ✅ Complete

All utilities created and tested:
- ✅ Password authentication flow working
- ✅ Account management utilities functional
- ✅ Auto-cleanup on test completion
- ✅ Proper error handling and logging
- ✅ Windows utilities created (requires admin testing)
