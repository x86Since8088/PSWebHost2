# Schema Management & Relationship Utilities

## Overview
Comprehensive utilities for managing users, groups, roles, and authentication providers with proper relationship validation and referential integrity.

## Schema Improvements Applied

### Foreign Key Constraints Added
The schema now includes proper foreign key relationships with cascade delete rules:

1. **LoginSessions → Users** - CASCADE delete (sessions deleted when user deleted)
2. **User_Groups_Map → Users** - CASCADE delete (group memberships removed when user deleted)
3. **User_Groups_Map → User_Groups** - CASCADE delete (memberships removed when group deleted)
4. **AuthenticationMethods → Users** - CASCADE delete (legacy auth methods removed with user)
5. **auth_user_provider → Users** - CASCADE delete (provider relationships removed with user)
6. **card_settings → Users** - CASCADE delete (card settings removed with user)
7. **CardSessions → LoginSessions** - SET NULL (card sessions persist but session reference cleared)
8. **CardSessions → Users** - SET NULL (card sessions persist but user reference cleared)

### NOT NULL Constraints Added
Critical fields now enforce NOT NULL:

- **auth_user_provider**: UserID, UserName, provider
- **User_Groups**: Name (with UNIQUE)
- **account_email_confirmation**: email

### CHECK Constraints Added
- **PSWeb_Roles.PrincipalType** - Must be 'User' or 'Group'

### DEFAULT Values Added
- **auth_user_provider.locked_out** - DEFAULT 0
- **auth_user_provider.enabled** - DEFAULT 1
- **LastLoginAttempt.UserViolationsCount** - DEFAULT 0
- **LastLoginAttempt.IPViolationCount** - DEFAULT 0

---

## Utility Scripts

### Group Management

#### Groups_New.ps1
Creates a new user group.

```powershell
# Create a group
.\system\utility\Groups_New.ps1 -GroupName "Administrators" -Description "System administrators"

# Returns:
# GroupID      : 3fa85f64-5717-4562-b3fc-2c963f66afa6
# Name         : Administrators
# Created      : 2025-12-29T03:45:00.000Z
# Updated      : 2025-12-29T03:45:00.000Z
# Description  : System administrators
```

#### Groups_Get.ps1
Retrieves groups from the database.

```powershell
# Get by GroupID
.\system\utility\Groups_Get.ps1 -GroupID "3fa85f64-..."

# Get by name
.\system\utility\Groups_Get.ps1 -GroupName "Administrators"

# List all groups
.\system\utility\Groups_Get.ps1 -ListAll

# Get groups a user belongs to
.\system\utility\Groups_Get.ps1 -UserID "user-id-here"
```

**Returns:** Group objects with MemberCount and Description properties added.

#### Groups_Remove.ps1
Removes a group and all associated relationships.

```powershell
# Remove with confirmation
.\system\utility\Groups_Remove.ps1 -GroupID "3fa85f64-..."

# Remove without confirmation
.\system\utility\Groups_Remove.ps1 -GroupID "3fa85f64-..." -Force
```

**Cleanup Actions:**
- Removes all user-group mappings
- Removes all role assignments to this group
- Removes group data from User_Data
- Removes the group record

#### Groups_AddUser.ps1
Adds a user to a group.

```powershell
.\system\utility\Groups_AddUser.ps1 -UserID "user-id" -GroupID "group-id"

# Returns:
# UserID      : user-id
# UserEmail   : user@example.com
# GroupID     : group-id
# GroupName   : Administrators
# Added       : 12/29/2025 3:45:00 AM
```

#### Groups_RemoveUser.ps1
Removes a user from a group.

```powershell
# Remove with confirmation
.\system\utility\Groups_RemoveUser.ps1 -UserID "user-id" -GroupID "group-id"

# Remove without confirmation
.\system\utility\Groups_RemoveUser.ps1 -UserID "user-id" -GroupID "group-id" -Force
```

---

### Role Management

#### Roles_New.ps1
Assigns a role to a user or group.

```powershell
# Assign role to user
.\system\utility\Roles_New.ps1 -PrincipalID "user-id" -PrincipalType User -RoleName "Admin"

# Assign role to group
.\system\utility\Roles_New.ps1 -PrincipalID "group-id" -PrincipalType Group -RoleName "Editor"

# Returns:
# PrincipalID   : user-id
# PrincipalType : User
# PrincipalName : user@example.com
# RoleName      : Admin
# Assigned      : 12/29/2025 3:45:00 AM
```

#### Roles_Get.ps1
Retrieves role assignments.

```powershell
# Get roles for a principal (user or group)
.\system\utility\Roles_Get.ps1 -PrincipalID "principal-id"

# Get all assignments for a specific role
.\system\utility\Roles_Get.ps1 -RoleName "Admin"

# Get all user's roles including inherited from groups
.\system\utility\Roles_Get.ps1 -UserID "user-id" -ExpandGroups

# List all unique role names
.\system\utility\Roles_Get.ps1 -ListRoles

# List all role assignments
.\system\utility\Roles_Get.ps1 -ListAll
```

**ExpandGroups Feature:** When querying by UserID with `-ExpandGroups`, returns both directly assigned roles and roles inherited from groups the user belongs to.

#### Roles_Remove.ps1
Removes a role assignment.

```powershell
# Remove with confirmation
.\system\utility\Roles_Remove.ps1 -PrincipalID "principal-id" -RoleName "Admin"

# Remove without confirmation
.\system\utility\Roles_Remove.ps1 -PrincipalID "principal-id" -RoleName "Admin" -Force
```

---

### User-Provider Relationship Management

#### UserProviders_Get.ps1
Retrieves user-provider relationships.

```powershell
# Get all providers for a user
.\system\utility\UserProviders_Get.ps1 -UserID "user-id"

# Get by email
.\system\utility\UserProviders_Get.ps1 -Email "user@example.com"

# Get all users of a specific provider
.\system\utility\UserProviders_Get.ps1 -Provider "Password"

# List all user-provider relationships
.\system\utility\UserProviders_Get.ps1 -ListAll

# Include user details in output
.\system\utility\UserProviders_Get.ps1 -Provider "Windows" -IncludeUserDetails
```

**Returns:** Provider records with:
- CreatedDateTime (converted from Unix timestamp)
- ExpiresDateTime (converted from Unix timestamp)
- ParsedData (JSON parsed from data column)

#### UserProviders_Remove.ps1
Removes a user-provider relationship.

```powershell
# Remove provider relationship
.\system\utility\UserProviders_Remove.ps1 -UserID "user-id" -Provider "Password"

# Remove provider and delete user if it's their last provider
.\system\utility\UserProviders_Remove.ps1 -UserID "user-id" -Provider "Password" -RemoveUserIfLastProvider

# Force removal without confirmation
.\system\utility\UserProviders_Remove.ps1 -UserID "user-id" -Provider "Windows" -Force
```

**Important:** If `-RemoveUserIfLastProvider` is specified and this is the user's only authentication method, the user account will be completely deleted including:
- User record
- All sessions
- All group memberships
- All role assignments
- All user data

---

### Database Validation

#### Database_ValidateRelationships.ps1
Validates referential integrity across all tables.

```powershell
# Check for orphaned records
.\system\utility\Database_ValidateRelationships.ps1

# Check with detailed output
.\system\utility\Database_ValidateRelationships.ps1 -Detailed

# Check and automatically fix orphans
.\system\utility\Database_ValidateRelationships.ps1 -FixOrphans
```

**Validation Checks:**
1. **auth_user_provider → Users** - Orphaned provider records
2. **User_Groups_Map → Users** - Orphaned user mappings
3. **User_Groups_Map → User_Groups** - Orphaned group mappings
4. **PSWeb_Roles (User) → Users** - Orphaned user role assignments
5. **PSWeb_Roles (Group) → User_Groups** - Orphaned group role assignments
6. **LoginSessions → Users** - Orphaned sessions
7. **User_Data → Users/Groups** - Orphaned user data

**Example Output:**
```
========================================
Database Relationship Validation
========================================

[1/7] Validating auth_user_provider -> Users...
  ✓ No issues found
[2/7] Validating User_Groups_Map -> Users...
  ✓ No issues found
[3/7] Validating User_Groups_Map -> User_Groups...
  ✓ No issues found
[4/7] Validating PSWeb_Roles (User) -> Users...
  ✓ No issues found
[5/7] Validating PSWeb_Roles (Group) -> User_Groups...
  ✓ No issues found
[6/7] Validating LoginSessions -> Users...
  ✓ No issues found
[7/7] Validating User_Data -> Users/Groups...
  ✓ No issues found

========================================
Validation Summary
========================================
✓ All relationship validations passed!
  Database integrity is intact.
========================================
```

---

## Usage Examples

### Create a Group and Assign Roles

```powershell
# 1. Create a group
$group = .\system\utility\Groups_New.ps1 -GroupName "ContentEditors" -Description "Users who can edit content"

# 2. Add users to the group
.\system\utility\Groups_AddUser.ps1 -UserID "user-1" -GroupID $group.GroupID
.\system\utility\Groups_AddUser.ps1 -UserID "user-2" -GroupID $group.GroupID

# 3. Assign a role to the group
.\system\utility\Roles_New.ps1 -PrincipalID $group.GroupID -PrincipalType Group -RoleName "Editor"

# 4. Verify user inherited the role
.\system\utility\Roles_Get.ps1 -UserID "user-1" -ExpandGroups
```

### Audit User Access

```powershell
# Get user information
$user = Get-PSWebHostUser -Email "user@example.com"

# Get all authentication providers
$providers = .\system\utility\UserProviders_Get.ps1 -UserID $user.UserID

# Get all groups the user belongs to
$groups = .\system\utility\Groups_Get.ps1 -UserID $user.UserID

# Get all roles (direct and inherited)
$roles = .\system\utility\Roles_Get.ps1 -UserID $user.UserID -ExpandGroups

# Display summary
Write-Host "User: $($user.Email)" -ForegroundColor Cyan
Write-Host "Providers: $($providers.provider -join ', ')" -ForegroundColor Yellow
Write-Host "Groups: $($groups.Name -join ', ')" -ForegroundColor Yellow
Write-Host "Roles: $($roles.RoleName -join ', ')" -ForegroundColor Yellow
```

### Remove User Completely

```powershell
$user = Get-PSWebHostUser -Email "user@example.com"

# Get all providers
$providers = .\system\utility\UserProviders_Get.ps1 -UserID $user.UserID

# Remove each provider, deleting user when last provider removed
foreach ($provider in $providers) {
    .\system\utility\UserProviders_Remove.ps1 `
        -UserID $user.UserID `
        -Provider $provider.provider `
        -RemoveUserIfLastProvider `
        -Force
}
```

### Validate Database Integrity

```powershell
# Run validation
$result = .\system\utility\Database_ValidateRelationships.ps1 -Detailed

# Check result
if ($result.DatabaseIntact) {
    Write-Host "Database is intact" -ForegroundColor Green
} else {
    Write-Host "Found $($result.TotalIssues) issues:" -ForegroundColor Red
    $result.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }

    # Fix automatically
    .\system\utility\Database_ValidateRelationships.ps1 -FixOrphans
}
```

---

## Integration with Existing Systems

### Account Management Scripts
These new utilities complement the existing account management scripts:

**Password Provider:**
- `Account_AuthProvider_Password_New.ps1`
- `Account_AuthProvider_Password_Get.ps1`
- `Account_AuthProvider_Password_Remove.ps1`
- `Account_AuthProvider_Password_RemoveTestingAccounts.ps1`

**Windows Provider:**
- `Account_AuthProvider_Windows_New.ps1`
- `Account_AuthProvider_Windows_Get.ps1`
- `Account_AuthProvider_Windows_Remove.ps1`
- `Account_AuthProvider_Windows_RemoveTestingAccounts.ps1`

### PowerShell Module Functions
The utilities work alongside existing module functions:

**PSWebHost_Authentication.psm1:**
- `Get-PSWebHostUser` - Get user by email/UserID
- `Register-PSWebHostUser` - Create user with provider
- `Get-PSWebHostRole` - Get user roles (now enhanced with group role inheritance)
- `Get-UserAuthenticationMethods` - List user's auth providers

---

## Files Created

```
system/utility/
├── Groups_New.ps1                        # Create group
├── Groups_Get.ps1                        # Query groups
├── Groups_Remove.ps1                     # Delete group
├── Groups_AddUser.ps1                    # Add user to group
├── Groups_RemoveUser.ps1                 # Remove user from group
├── Roles_New.ps1                         # Assign role
├── Roles_Get.ps1                         # Query roles
├── Roles_Remove.ps1                      # Remove role assignment
├── UserProviders_Get.ps1                 # Query user-provider relationships
├── UserProviders_Remove.ps1              # Remove provider relationship
├── Database_ValidateRelationships.ps1    # Validate database integrity
└── SCHEMA_MANAGEMENT_SUMMARY.md          # This file

system/db/sqlite/
└── sqliteconfig.json                     # Updated with foreign keys and constraints
```

---

## Schema Changes Summary

### Before
- No foreign key constraints
- Missing NOT NULL constraints on critical fields
- No CHECK constraints for enum-like fields
- No DEFAULT values
- Orphaned records possible

### After
- ✅ Foreign keys with CASCADE/SET NULL rules
- ✅ NOT NULL constraints on UserID, provider, UserName, etc.
- ✅ CHECK constraint on PrincipalType ('User' or 'Group')
- ✅ DEFAULT values for locked_out, enabled, violation counts
- ✅ Automatic orphan prevention via CASCADE deletes
- ✅ Validation utilities to detect and fix existing orphans

---

## Best Practices

1. **Always validate before major operations:**
   ```powershell
   .\system\utility\Database_ValidateRelationships.ps1 -Detailed
   ```

2. **Use Groups for role management:**
   - Assign roles to groups, not individual users when possible
   - Users inherit roles from all groups they belong to

3. **Check provider count before removal:**
   - Users need at least one authentication provider to log in
   - Use `-RemoveUserIfLastProvider` carefully

4. **Use -WhatIf for safety:**
   ```powershell
   .\system\utility\Groups_Remove.ps1 -GroupID "id" -WhatIf
   ```

5. **Backup before bulk operations:**
   - Always backup the database before running bulk cleanup scripts

---

## Status: ✅ Complete

All utilities created and schema updated with:
- ✅ Group management (create, get, remove, add/remove users)
- ✅ Role management (assign, get, remove)
- ✅ User-Provider relationship management
- ✅ Database relationship validation
- ✅ Foreign key constraints
- ✅ NOT NULL and CHECK constraints
- ✅ DEFAULT values
- ✅ CASCADE delete rules
- ✅ Comprehensive documentation
