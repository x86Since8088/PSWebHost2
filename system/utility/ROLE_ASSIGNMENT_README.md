# Role Assignment Management Scripts

Command-line utilities for managing role assignments in PSWebHost.

## Overview

These scripts provide a comprehensive interface for managing user and group role assignments from the command line. All scripts support PowerShell's common parameters like `-Verbose`, `-WhatIf`, and `-Confirm`.

## Scripts

### RoleAssignment_New.ps1
Assigns a role to a user or group.

**Basic Usage:**
```powershell
# Assign by UserID
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_New.ps1' -PrincipalID '6ec71a85-fb79-4ebc-aa1d-587c7f8b403c' -PrincipalType 'User' -RoleName 'Debug'"

# Assign by Email (easier!)
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_New.ps1' -Email 'admin@test.com' -RoleName 'Admin'"

# Assign and return the result
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_New.ps1' -Email 'test@localhost' -RoleName 'Debug' -PassThru"
```

**Parameters:**
- `-PrincipalID` - UserID or GroupID (GUID)
- `-Email` - User's email address (alternative to PrincipalID)
- `-PrincipalType` - 'User' or 'Group'
- `-RoleName` - Name of the role to assign
- `-CreateRoleIfMissing` - Create the role if it doesn't exist
- `-PassThru` - Return the assignment object

### RoleAssignment_Get.ps1
Retrieves role assignments with flexible filtering.

**Basic Usage:**
```powershell
# Get roles for a user by email
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -Email 'admin@test.com'"

# Get all users/groups with a specific role
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -RoleName 'Debug'"

# List all unique role names
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -ListRoles"

# List all assignments
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -ListAll"

# Get user roles including from group memberships
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -Email 'test@localhost' -ExpandGroups"

# Export as JSON
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -Email 'admin@test.com' -Format Json"
```

**Parameters:**
- `-PrincipalID` - Get roles for specific principal
- `-Email` - Get roles for user by email
- `-RoleName` - Get all principals with this role
- `-UserID` - Get roles for specific user
- `-ListAll` - List all role assignments
- `-ListRoles` - List all unique role names
- `-ExpandGroups` - Include roles from group memberships
- `-Format` - Output format: 'Table', 'List', 'Json', or 'Simple'

### RoleAssignment_Remove.ps1
Removes role assignments.

**Basic Usage:**
```powershell
# Remove by email (with confirmation)
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Remove.ps1' -Email 'test@localhost' -RoleName 'Admin'"

# Remove without confirmation
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Remove.ps1' -Email 'test@localhost' -RoleName 'Debug' -Force"

# Preview what would be removed
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Remove.ps1' -Email 'admin@test.com' -RoleName 'Admin' -WhatIf"

# Remove a role from ALL principals
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Remove.ps1' -RoleName 'OldRole' -RemoveAll -Force"
```

**Parameters:**
- `-PrincipalID` - UserID or GroupID to remove role from
- `-Email` - User's email address
- `-RoleName` - Role name to remove
- `-RemoveAll` - Remove this role from all principals
- `-Force` - Skip confirmation prompts
- `-WhatIf` - Preview changes without making them

### RoleAssignment_List.ps1
Comprehensive listing with statistics and grouping.

**Basic Usage:**
```powershell
# List all assignments
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1'"

# Show statistics
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -ShowStatistics"

# Group by role
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -GroupBy Role"

# Group by user
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -GroupBy User"

# Filter by role name
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -RoleFilter 'Admin'"

# Filter by user pattern
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -UserFilter 'test@*'"

# Export to CSV
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -Export 'C:\temp\roles.csv'"
```

**Parameters:**
- `-GroupBy` - Group by: 'None', 'Role', 'User', or 'Group'
- `-ShowStatistics` - Display summary statistics
- `-RoleFilter` - Filter by role name (supports wildcards)
- `-UserFilter` - Filter by user pattern (supports wildcards)
- `-Export` - Export to CSV file

### RoleAssignment_Update.ps1
Bulk updates and synchronization.

**Basic Usage:**
```powershell
# Add multiple roles
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Update.ps1' -Email 'admin@test.com' -AddRoles 'Admin','Debug','site_admin'"

# Remove multiple roles
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Update.ps1' -Email 'user@test.com' -RemoveRoles 'Admin','site_admin'"

# Set exact roles (replace all existing)
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Update.ps1' -Email 'test@localhost' -SetRoles 'authenticated','Debug'"

# Import from JSON file
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Update.ps1' -FromFile 'C:\temp\roles.json'"
```

**Parameters:**
- `-PrincipalID` - UserID or GroupID
- `-Email` - User's email address
- `-AddRoles` - Array of roles to add
- `-RemoveRoles` - Array of roles to remove
- `-SetRoles` - Array of roles to set (replaces all)
- `-FromFile` - Import from JSON or CSV file
- `-Sync` - Synchronize database to match file exactly

## Common Use Cases

### Initial Setup: Add Debug Role to Your Account

```powershell
# Method 1: Using email (easiest)
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_New.ps1' -Email 'your-email@test.com' -RoleName 'Debug'"

# Method 2: Using UserID
# First, find your UserID
pwsh -Command "Import-Module PSSQLite; Invoke-SqliteQuery -DataSource 'C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db' -Query 'SELECT UserID, Email FROM Users'"

# Then assign the role
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_New.ps1' -PrincipalID 'YOUR-USER-ID-HERE' -PrincipalType 'User' -RoleName 'Debug'"
```

### View Your Current Roles

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -Email 'your-email@test.com'"
```

### Add Multiple Admin Roles

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Update.ps1' -Email 'admin@test.com' -AddRoles 'Admin','Debug','site_admin','system_admin'"
```

### Audit All Role Assignments

```powershell
# Show comprehensive statistics
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -ShowStatistics"

# Group by role to see who has what
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -GroupBy Role"

# Export for review
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -Export 'C:\temp\role-audit.csv'"
```

### Clean Up Old Roles

```powershell
# Preview what will be removed
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Remove.ps1' -RoleName 'OldRole' -RemoveAll -WhatIf"

# Actually remove it
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Remove.ps1' -RoleName 'OldRole' -RemoveAll -Force"
```

### Backup and Restore Roles

```powershell
# Backup (export all roles)
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -ListAll -Format Json" > roles-backup.json

# Restore (import from backup)
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Update.ps1' -FromFile 'roles-backup.json'"
```

## Available Roles

Common roles in PSWebHost:

| Role Name | Description | Menu Access |
|-----------|-------------|-------------|
| `authenticated` | Basic authenticated user | Main Menu |
| `Admin` | Administrator | Admin Tools, All Features |
| `Debug` | Debug/Developer access | Admin Tools, Error Details |
| `site_admin` | Site administrator | Site Admin Menu, Admin Tools |
| `system_admin` | System administrator | System Admin Menu, Admin Tools |

Custom roles can be created by simply assigning them - they don't need to be pre-defined.

## JSON File Format

For bulk imports with `RoleAssignment_Update.ps1 -FromFile`:

```json
[
  {
    "Email": "admin@test.com",
    "RoleName": "Admin"
  },
  {
    "Email": "admin@test.com",
    "RoleName": "Debug"
  },
  {
    "PrincipalID": "6ec71a85-fb79-4ebc-aa1d-587c7f8b403c",
    "PrincipalType": "User",
    "RoleName": "site_admin"
  }
]
```

## CSV File Format

For bulk imports with `RoleAssignment_Update.ps1 -FromFile`:

```csv
Email,RoleName
admin@test.com,Admin
admin@test.com,Debug
test@localhost,Debug
```

## Tips

1. **Use Email Parameter**: It's easier than looking up GUIDs
2. **Use -PassThru**: When scripting, to capture the result
3. **Use -WhatIf**: Always preview destructive operations first
4. **Use -Verbose**: To see detailed execution information
5. **Export Regularly**: Keep backups of your role assignments
6. **Group Memberships**: Use `-ExpandGroups` to see inherited roles

## Troubleshooting

### "User not found"
- Double-check the email address or UserID
- Use `RoleAssignment_Get.ps1 -ListAll` to see all users with roles
- Query the database directly to find users:
  ```powershell
  pwsh -Command "Import-Module PSSQLite; Invoke-SqliteQuery -DataSource 'C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db' -Query 'SELECT UserID, Email FROM Users'"
  ```

### "Role already assigned"
- This is just a warning, not an error
- The role assignment already exists
- Use `-Verbose` to see confirmation messages

### Changes not reflecting in UI
- Log out and log back in
- Clear browser cookies
- Check that you're using the correct user account
- Verify the role was actually added:
  ```powershell
  pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -Email 'your-email@test.com'"
  ```

## See Also

- `ADMIN_MENU_SETUP.md` - Setting up admin access
- `system/utility/Roles_*.ps1` - Legacy role management scripts (still functional)
- Database schema: `PsWebHost_Data/pswebhost.db` - Tables: `PSWeb_Roles`, `Users`, `User_Groups`
