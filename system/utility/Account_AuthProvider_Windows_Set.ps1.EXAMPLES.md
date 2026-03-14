# Account_AuthProvider_Windows_Set.ps1 - Usage Examples

## Overview

This script updates Windows authentication provider accounts in the PSWebHost database. It's particularly useful after computer renames when the Windows username includes the computer name.

## Common Scenarios

### 1. Fix Account After Computer Rename

**Problem**: Computer was renamed from `W11` to `NEWNAME`, breaking the Windows auth account `test@w11`

**Solution**: Update the UserName to reflect the new computer name

```powershell
# First, find the user's ID
.\system\utility\Account_AuthProvider_Windows_Get.ps1 -UserName "test@w11"

# Update the UserName to match current computer
.\system\utility\Account_AuthProvider_Windows_Set.ps1 -ID "user-id-here" -UserName "test@$env:COMPUTERNAME" -Verbose

# Or if you want to update the Email too:
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -UserName "test@$env:COMPUTERNAME" `
    -Email "test@$env:COMPUTERNAME" `
    -Verbose
```

### 2. Update Local Windows User Too

If you also need to rename the local Windows user:

```powershell
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -UserName "test@$env:COMPUTERNAME" `
    -Email "test@$env:COMPUTERNAME" `
    -UpdateLocalUser `
    -Verbose
```

### 3. Lock Out an Account

```powershell
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -LockedOut $true `
    -Verbose
```

### 4. Unlock an Account

```powershell
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -LockedOut $false `
    -Verbose
```

### 5. Disable an Account

```powershell
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -Enabled $false `
    -Verbose
```

### 6. Update Multiple Fields at Once

```powershell
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -Email "newemail@example.com" `
    -UserName "newusername" `
    -Enabled $true `
    -LockedOut $false `
    -Owner "admin" `
    -OwnerType "User" `
    -Verbose
```

### 7. Update with Force (No Confirmation)

```powershell
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -UserName "test@$env:COMPUTERNAME" `
    -Force
```

### 8. Reset Local Windows User Password

```powershell
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID "user-id-here" `
    -NewLocalPassword "NewSecurePassword123!" `
    -Verbose
```

## Complete Workflow: Fix Test Account After Rename

```powershell
# Step 1: Check current computer name
$env:COMPUTERNAME
# Output example: NEWNAME

# Step 2: Find the broken account
$account = .\system\utility\Account_AuthProvider_Windows_Get.ps1 -ListAll |
    Where-Object { $_.UserName -like "test@*" }

Write-Host "Found account: $($account.Email) with UserName: $($account.UserName)"
Write-Host "UserID: $($account.UserID)"

# Step 3: Update the account
.\system\utility\Account_AuthProvider_Windows_Set.ps1 `
    -ID $account.UserID `
    -UserName "test@$env:COMPUTERNAME" `
    -Email "test@$env:COMPUTERNAME" `
    -Verbose

# Step 4: Verify the update
$updated = .\system\utility\Account_AuthProvider_Windows_Get.ps1 -UserID $account.UserID
Write-Host "`nUpdated account:"
Write-Host "  Email: $($updated.Email)"
Write-Host "  UserName: $($updated.UserName)"
Write-Host "  Enabled: $($updated.enabled)"
Write-Host "  LockedOut: $($updated.locked_out)"
```

## Parameters Reference

### Required Parameters

- **`-ID`** (or `-UserID`): The UserID of the account to update (required, position 0)

### Users Table Fields

- **`-Email`**: Update the email address (must be unique)
- **`-Owner`**: Update the owner field
- **`-OwnerType`**: Update owner type (valid values: 'User', 'Group', 'System')

### auth_user_provider Table Fields

- **`-UserName`**: Update the Windows username (the name stored in the database)
- **`-Enabled`**: Enable/disable the account ($true/$false, 1/0)
- **`-LockedOut`**: Lock/unlock the account ($true/$false, 1/0)
- **`-Expires`**: Set expiration date (text/datetime string)
- **`-Data`**: Update custom data field (JSON string)

### Control Parameters

- **`-Force`**: Skip confirmation prompt
- **`-UpdateLocalUser`**: Also rename the local Windows user (requires admin)
- **`-NewLocalPassword`**: Set new password for local Windows user (requires admin)

## Output

The script returns the updated user object with additional properties:

- `UpdatedFields`: Array of fields that were changed
- `UpdateDate`: Timestamp of the update
- `Changes`: Array of change descriptions

## Error Handling

The script will fail with clear error messages if:

- User ID doesn't exist
- User is not a Windows provider account
- New email is already in use by another user
- Local Windows user rename fails (if `-UpdateLocalUser` specified)
- Database update fails

Warnings are shown for:

- Local Windows user doesn't exist (when `-UpdateLocalUser` specified)
- No changes were specified

## Notes

1. **Requires Administrator**: The script requires `-RunAsAdministrator` for local user operations
2. **Case-Insensitive**: UserID lookups are case-insensitive
3. **Transaction Safety**: Database updates are atomic - either all succeed or all fail
4. **Validation**: Email uniqueness is validated before update
5. **Verbose Output**: Use `-Verbose` to see detailed operation logs

## Troubleshooting

### Issue: "User with ID 'xyz' not found"

**Cause**: Invalid UserID or user is not a Windows provider account

**Solution**: Use `Account_AuthProvider_Windows_Get.ps1` to find the correct ID

### Issue: "Email 'xyz@example.com' is already in use"

**Cause**: Another user already has that email address

**Solution**: Choose a different email or check if there's a duplicate account

### Issue: "Local Windows user 'test@w11' does not exist"

**Cause**: Local Windows user was manually deleted or never existed

**Solution**: Remove the `-UpdateLocalUser` flag to update database only

### Issue: Access Denied when renaming local user

**Cause**: Script not running as Administrator

**Solution**: Run PowerShell as Administrator

## Related Scripts

- **`Account_AuthProvider_Windows_Get.ps1`**: Query Windows auth accounts
- **`Account_AuthProvider_Windows_New.ps1`**: Create new Windows auth accounts
- **`Account_AuthProvider_Windows_Remove.ps1`**: Delete Windows auth accounts

## See Also

- PSWebHost Authentication Documentation
- Windows User Management
- Database Schema Reference
