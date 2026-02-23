# API Key Ownership and Role Management Implementation

**Date**: 2026-01-23
**Status**: ✅ Complete and Tested

---

## Overview

Implemented comprehensive API key ownership and role management system following the architecture where each API key has a dedicated user account owned by the requesting user/group.

---

## Key Changes

### 1. Database Schema Updates

#### Updated `system/db/sqlite/sqliteconfig.json`

**Users Table** - Added ownership tracking:
```json
{ "name": "Owner", "type": "TEXT", "constraint": "" },
{ "name": "OwnerType", "type": "TEXT", "constraint": "DEFAULT 'User'" }
```

**API_Keys Table** - Added ownership tracking:
```json
{ "name": "Owner", "type": "TEXT", "constraint": "DEFAULT 'system'" },
{ "name": "OwnerType", "type": "TEXT", "constraint": "DEFAULT 'User'" }
```

**Migration**: Schema validator automatically adds new columns to existing tables

---

### 2. Utility Scripts

#### ✅ `system/utility/Account_Auth_BearerToken_New.ps1` (Completely Rewritten)

**Architecture Implementation**:
- Creates dedicated user account for each API key (email: `api_key_{name}_{random}@localhost`)
- Sets Owner on dedicated account (UserID or 'system')
- Assigns roles to dedicated account via `RoleAssignment_New.ps1`
- Links API_Keys record to dedicated account
- Updates API_Keys record with Owner info

**Parameters**:
```powershell
-Email              # Requesting user's email (resolved to Owner)
-UserID             # Requesting user's UserID (alternative to Email)
-Name               # API key name (required unless -TestAccount)
-Description        # API key description
-Owner              # Owner UserID/GroupID (defaults to requesting user)
-OwnerType          # 'User' or 'Group' (defaults to 'User')
-Roles              # Array of roles to assign to API key account
-AllowedIPs         # IP restrictions
-ExpiresAt          # Expiration date
-TestAccount        # Create test API key (Owner='system')
```

**Example Usage**:
```powershell
# Create API key for existing user with roles
.\system\utility\Account_Auth_BearerToken_New.ps1 `
    -Email "admin@test.com" `
    -Name "MyAPIKey" `
    -Roles @('admin','api_access') `
    -Description "API key for automation"

# Create test API key
.\system\utility\Account_Auth_BearerToken_New.ps1 -TestAccount -Roles @('debug')
```

**Output**:
```
✓ Bearer Token Created Successfully!
========================================
KeyID:              48c89231-bc63-49c1-995a-4f8c61bfd363
Name:               MyAPIKey
Dedicated Account:  api_key_MyAPIKey_f59ac4b6@localhost
Owner:              admin@test.com (User)
Roles:              admin, api_access
API Key:            gk8aJR5n4e8reYj+EijrREpWD41rWgxHmuR6lvfHFX0=
========================================
```

---

#### ✅ `system/utility/Account_Auth_BearerToken_Get_Enhanced.ps1` (Already Created)

**Features**:
- Lists API keys with roles via `RoleAssignment_Get.ps1`
- Shows owner information (User or Group)
- Filter by: KeyID, Name, UserID, Email, Owner
- Output formats: Table, List, Json, Detailed

**Parameters**:
```powershell
-KeyID              # Get specific API key by ID
-Name               # Get specific API key by name
-UserID             # Get all API keys for a user account
-OwnedBy            # Get all API keys owned by user/group
-Email              # Get API keys by linked user's email
-ListAll            # List all API keys
-IncludeDisabled    # Include disabled keys
-Format             # Table, List, Json, or Detailed
```

**Example Usage**:
```powershell
# List all keys owned by a user
.\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 `
    -OwnedBy "admin@test.com" `
    -Format Detailed

# Get specific key details
.\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 `
    -Name "MyAPIKey" `
    -Format Detailed
```

**Output**:
```
════════════════════════════════════════
API Key: MyAPIKey
════════════════════════════════════════
  KeyID: 48c89231-bc63-49c1-995a-4f8c61bfd363
  Linked User: api_key_MyAPIKey_f59ac4b6@localhost
  Owned By: admin@test.com (User)
  Roles: admin, api_access
  Enabled: True
  Created: 2026-01-23 16:03:08
  Description: API key for automation tasks
```

---

#### ✅ `system/utility/Account_Auth_BearerToken_Update.ps1` (Already Created)

**Features**:
- Update API key properties (name, description, expiration, IPs)
- Manage roles via `RoleAssignment_New.ps1` and `RoleAssignment_Remove.ps1`
- Change owner
- Enable/disable keys

**Example Usage**:
```powershell
# Add roles to API key
.\system\utility\Account_Auth_BearerToken_Update.ps1 `
    -Name "MyAPIKey" `
    -AddRoles @('site_admin')

# Update owner
.\system\utility\Account_Auth_BearerToken_Update.ps1 `
    -Name "MyAPIKey" `
    -SetOwner "newowner@test.com" `
    -OwnerType User
```

---

#### ✅ `system/utility/Migrate-ApiKeys-AddOwnerAndRoles.ps1` (Already Created)

**Purpose**: Database migration script to add Owner columns

**Usage**:
```powershell
# Dry run (see what would change)
.\system\utility\Migrate-ApiKeys-AddOwnerAndRoles.ps1 -WhatIf

# Apply changes
.\system\utility\Migrate-ApiKeys-AddOwnerAndRoles.ps1
```

**Note**: With the updated `sqliteconfig.json`, the schema validator automatically adds new columns, making this script optional for new installations.

---

### 3. Architecture Documentation

#### ✅ `apps/WebHostTaskManagement/API_KEY_ARCHITECTURE.md`

Complete architectural documentation including:
- Core principle: Each API key = dedicated user account
- Database schema design
- Workflow examples
- Security considerations
- Comparison: Before vs After
- Utility script reference

---

## Architecture Summary

```
Requesting User (admin@test.com) [Owner]
    └── Owns
        User (api_key_MyAPIKey_abc@localhost) [Dedicated Account]
        ├── Has independent roles (via PSWeb_Roles)
        └── Linked to
            API_Keys record
            └── Bearer token (hashed)
```

**Benefits**:
- ✅ Independent roles per API key
- ✅ Clear ownership tracking
- ✅ Easy vault integration
- ✅ Standard role management tools work
- ✅ Audit trail via user account
- ✅ No new junction tables needed

---

## Testing Results

### Test 1: Create Test API Key
```powershell
.\system\utility\Account_Auth_BearerToken_New.ps1 -TestAccount -Roles @('debug')
```

**Result**: ✅ Success
- Created dedicated account: `api_key_TestBearerKey_NKJnw_f7c8d063@localhost`
- Owner set to: `system`
- Role assigned: `debug`

---

### Test 2: Create API Key for Existing User
```powershell
# Create test user
.\system\utility\Account_AuthProvider_Password_New.ps1 -TestAccount
# Email: TA_Password_IJsZW@localhost

# Create API key owned by user
.\system\utility\Account_Auth_BearerToken_New.ps1 `
    -Email 'TA_Password_IJsZW@localhost' `
    -Name 'MyAPIKey' `
    -Roles @('admin','api_access') `
    -Description 'API key for automation tasks'
```

**Result**: ✅ Success
- Created dedicated account: `api_key_MyAPIKey_f59ac4b6@localhost`
- Owner set to: `f4901f47-6bfc-46fe-bc72-45fbe076fb68` (UserID of TA_Password_IJsZW@localhost)
- Roles assigned: `admin`, `api_access`

---

### Test 3: Query API Keys by Owner
```powershell
.\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 `
    -OwnedBy 'TA_Password_IJsZW@localhost' `
    -Format Detailed
```

**Result**: ✅ Success
- Found API key: MyAPIKey
- Showed owner: TA_Password_IJsZW@localhost (User)
- Showed roles: admin, api_access

---

## Integration Points

### Vault App Integration

**Query User's API Keys**:
```powershell
$userKeys = .\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 `
    -OwnedBy $sessiondata.UserID `
    -Format Json | ConvertFrom-Json

# Display in vault UI with manage options
foreach ($key in $userKeys) {
    # Show key details, roles, expiration, etc.
    # Allow user to:
    # - Update roles (if owner)
    # - Disable/enable
    # - Delete
    # - View last used timestamp
}
```

---

## File Locations

### Modified Files:
- `system/db/sqlite/sqliteconfig.json` - Added Owner columns to Users and API_Keys tables

### New/Rewritten Files:
- `system/utility/Account_Auth_BearerToken_New.ps1` - Complete rewrite with dedicated account creation
- `system/utility/Account_Auth_BearerToken_Get_Enhanced.ps1` - Already created (previous work)
- `system/utility/Account_Auth_BearerToken_Update.ps1` - Already created (previous work)
- `system/utility/Migrate-ApiKeys-AddOwnerAndRoles.ps1` - Already created (previous work)
- `apps/WebHostTaskManagement/API_KEY_ARCHITECTURE.md` - Already created (previous work)

---

## Next Steps for Users

1. **Run Migration** (if updating existing installation):
   ```powershell
   .\system\utility\Migrate-ApiKeys-AddOwnerAndRoles.ps1
   ```
   Or simply start the server - schema validator will add columns automatically.

2. **Create API Keys**:
   ```powershell
   # For yourself
   .\system\utility\Account_Auth_BearerToken_New.ps1 `
       -Email "your@email.com" `
       -Name "MyAPIKey" `
       -Roles @('debug','api_access')

   # For testing
   .\system\utility\Account_Auth_BearerToken_New.ps1 -TestAccount -Roles @('debug')
   ```

3. **View API Keys**:
   ```powershell
   # Your keys
   .\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 `
       -OwnedBy "your@email.com"

   # All keys (requires admin)
   .\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 -ListAll
   ```

4. **Manage API Keys**:
   ```powershell
   # Add roles
   .\system\utility\Account_Auth_BearerToken_Update.ps1 `
       -Name "MyAPIKey" `
       -AddRoles @('site_admin')

   # Disable key
   .\system\utility\Account_Auth_BearerToken_Update.ps1 `
       -Name "MyAPIKey" `
       -Disable
   ```

---

## Security Considerations

### Ownership Verification

Before allowing management operations, verify ownership:
```powershell
function Test-ApiKeyOwnership {
    param($KeyID, $RequestingUserID)

    $key = Get-ApiKey -KeyID $KeyID
    $keyUser = Get-User -UserID $key.UserID

    # Check if requesting user owns this key
    if ($keyUser.Owner -eq $RequestingUserID) {
        return $true
    }

    # Check if requesting user is system admin
    if (Test-UserHasRole -UserID $RequestingUserID -Role 'system_admin') {
        return $true
    }

    return $false
}
```

### Group Ownership

API keys can be owned by groups for team-shared keys:
```powershell
.\system\utility\Account_Auth_BearerToken_New.ps1 `
    -Owner "DevTeam" `
    -OwnerType Group `
    -Roles @('developer', 'api_access')

# All group members can manage the key
```

---

## Summary

**Status**: ✅ Complete and Tested

**Architecture**: Each API key has its own dedicated user account, owned by the requesting user/group

**Benefits**:
- Independent roles per API key (via PSWeb_Roles)
- Clear ownership tracking (Owner field)
- Easy vault integration (query by OwnedBy)
- Standard role management tools work
- Audit trail via user account
- No new junction tables needed

**Testing**: All functionality tested and working:
- ✅ Create test API keys
- ✅ Create API keys for existing users
- ✅ Query API keys by owner
- ✅ View API keys with roles
- ✅ Schema validator adds Owner columns automatically

**Ready for**: Production use and vault app integration
