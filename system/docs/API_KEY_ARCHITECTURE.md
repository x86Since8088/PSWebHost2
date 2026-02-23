# API Key Architecture - Owner and Roles

**Date**: 2026-01-23
**Version**: 2.0.0

---

## Architecture Overview

### Core Principle

**Each API key has its own dedicated user account.** That user account is "owned" by the requesting user/group.

```
Requesting User (admin@test.com)
    └── Owns → API Key User Account (api_key_user_abc@localhost)
        ├── Has Roles (via PSWeb_Roles table)
        └── Linked to → API_Keys record
            └── Contains Bearer Token (hashed)
```

---

## Benefits

1. **Simplified Role Management**: Uses existing `PSWeb_Roles` table - no new junction tables needed
2. **Ownership Tracking**: Clear accountability - who owns/manages each API key
3. **Vault Integration**: Users can see all API keys they own via vault app
4. **Standard Tools**: All existing RoleAssignment utilities work with API keys
5. **Audit Trail**: Standard user audit applies to API key accounts

---

## Database Schema

### Users Table (Enhanced)

```sql
ALTER TABLE Users ADD COLUMN Owner TEXT;          -- UserID or GroupID of owner
ALTER TABLE Users ADD COLUMN OwnerType TEXT;      -- 'User' or 'Group'
```

| Field | Type | Description |
|-------|------|-------------|
| UserID | TEXT | Primary key |
| Email | TEXT | User email (for API keys: `api_key_xxx@localhost`) |
| Owner | TEXT | UserID or GroupID of the owner (defaults to NULL for regular users) |
| OwnerType | TEXT | 'User' or 'Group' (defaults to 'User') |

### API_Keys Table (Enhanced)

```sql
ALTER TABLE API_Keys ADD COLUMN Owner TEXT DEFAULT 'system';
ALTER TABLE API_Keys ADD COLUMN OwnerType TEXT DEFAULT 'User';
```

| Field | Type | Description |
|-------|------|-------------|
| KeyID | TEXT | Primary key |
| Name | TEXT | Human-readable name |
| KeyHash | TEXT | SHA256 hash of Bearer token |
| UserID | TEXT | **Links to dedicated user account** |
| Owner | TEXT | **Owner of this key** (UserID/GroupID) |
| OwnerType | TEXT | **'User' or 'Group'** |
| AllowedIPs | TEXT | Comma-separated IP restrictions |
| CreatedBy | TEXT | Who created the key |
| CreatedAt | DATETIME | Creation timestamp |
| ExpiresAt | DATETIME | Optional expiration |
| LastUsed | DATETIME | Last authentication |
| Enabled | INTEGER | 1=enabled, 0=disabled |
| Description | TEXT | Optional description |

### PSWeb_Roles Table (Existing - No Changes)

Roles are assigned to the API key's user account via the existing `PSWeb_Roles` table:

```sql
-- Assign role to API key's user account
INSERT INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName)
VALUES ('{api_key_user_id}', 'User', 'debug');
```

---

## Workflow Examples

### Create API Key for Existing User

```powershell
# User admin@test.com requests an API key
.\system\utility\Account_Auth_BearerToken_New.ps1 `
    -Email "admin@test.com" `          # Link to existing user
    -Name "AdminAPIKey" `
    -Owner "admin@test.com" `          # Owner (who manages it)
    -Roles @('admin', 'site_admin') `  # Independent roles
    -Description "Admin automation key"

# Creates:
# 1. New user account: api_key_AdminAPIKey_xyz@localhost
#    - Owner: admin@test.com
#    - Roles: admin, site_admin (via PSWeb_Roles)
# 2. API_Keys record:
#    - UserID: {new user account ID}
#    - Owner: admin@test.com
#    - KeyHash: {hashed bearer token}
# 3. Returns: Bearer token (only shown once)
```

### Update API Key Roles

```powershell
# Add debug role to the API key
.\system\utility\Account_Auth_BearerToken_Update.ps1 `
    -Name "AdminAPIKey" `
    -AddRoles @('debug')

# Internally calls:
.\system\utility\RoleAssignment_New.ps1 `
    -PrincipalID {api_key_user_id} `
    -PrincipalType User `
    -RoleName 'debug'
```

### List API Keys Owned by User

```powershell
# Show all API keys owned by admin@test.com
.\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 `
    -OwnedBy "admin@test.com" `
    -Format Detailed

# Output shows:
# - API key name
# - Linked user account
# - Owner
# - Roles (from PSWeb_Roles)
# - Expiration, IPs, etc.
```

### Vault Integration

```powershell
# In vault app, show user's API keys:
$userKeys = .\system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1 `
    -OwnedBy $sessiondata.UserID `
    -Format Json | ConvertFrom-Json

# Display in vault UI with manage options:
# - View key details
# - Update roles (if owner)
# - Disable/enable
# - Delete
# - View last used timestamp
```

---

## Migration

### Run Migration Script

```powershell
# Dry run (see what would change)
.\system\utility\Migrate-ApiKeys-AddOwnerAndRoles.ps1 -WhatIf

# Apply changes
.\system\utility\Migrate-ApiKeys-AddOwnerAndRoles.ps1
```

**Changes Made**:
1. Adds `Owner` and `OwnerType` columns to `Users` table
2. Adds `Owner` and `OwnerType` columns to `API_Keys` table (backward compatible)
3. Existing API keys: Owner defaults to 'system'
4. Existing users: Owner remains NULL (not owned)

---

## API Key Lifecycle

### Creation

1. User requests API key via utility or vault app
2. System creates dedicated user account with Owner set
3. Roles assigned to user account via `PSWeb_Roles`
4. API_Keys record created linking to user account
5. Bearer token generated and returned (only once)

### Authentication

1. Request includes `Authorization: Bearer <token>`
2. System hashes token and looks up in `API_Keys` table
3. Retrieves linked user account (via `UserID`)
4. Loads roles from `PSWeb_Roles` for that user
5. Creates session with user's roles
6. Request proceeds with authenticated session

### Management

Owner can:
- View all owned API keys
- Update key properties (name, description, expiration)
- Add/remove roles from key's user account
- Disable/enable keys
- Delete keys (removes user account and API_Keys record)

System admins can:
- View all API keys
- Manage any key
- Transfer ownership
- Audit key usage

---

## Security Considerations

### Ownership Verification

```powershell
# Before allowing management operations, verify ownership:
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

```powershell
# API key can be owned by a group
.\system\utility\Account_Auth_BearerToken_New.ps1 `
    -Owner "DevTeam" `
    -OwnerType Group `
    -Roles @('developer', 'api_access')

# All group members can manage the key
# Useful for team-shared API keys
```

---

## Comparison: Before vs After

### Before (v1)

```
API_Keys
├── UserID → User (roles inherited from user)
└── No ownership tracking
```

**Issues**:
- API key roles tied to user roles
- No way to know who manages a key
- Difficult vault integration
- Can't give API key independent permissions

### After (v2)

```
User (admin@test.com) [Owner]
    └── Owns
        User (api_key_xyz@localhost) [Owned Account]
        ├── Has independent roles (via PSWeb_Roles)
        └── Linked to
            API_Keys record
            └── Bearer token
```

**Benefits**:
- ✅ Independent roles per API key
- ✅ Clear ownership tracking
- ✅ Easy vault integration
- ✅ Standard role management tools work
- ✅ Audit trail via user account

---

## Utility Scripts

| Script | Purpose |
|--------|---------|
| `Account_Auth_BearerToken_New.ps1` | Create API key with owner and roles |
| `Account_Auth_BearerToken_Get_Enhanced.ps1` | List keys with roles and ownership |
| `Account_Auth_BearerToken_Update.ps1` | Update key properties and roles |
| `Account_Auth_BearerToken_Remove.ps1` | Delete key and user account |
| `Migrate-ApiKeys-AddOwnerAndRoles.ps1` | Database migration script |

---

## Summary

- ✅ Each API key = dedicated user account
- ✅ User account owned by requesting user/group
- ✅ Roles managed via existing `PSWeb_Roles` table
- ✅ Owner can manage all their API keys
- ✅ Perfect for vault integration
- ✅ Uses standard RoleAssignment utilities

**Status**: Ready for implementation and testing
