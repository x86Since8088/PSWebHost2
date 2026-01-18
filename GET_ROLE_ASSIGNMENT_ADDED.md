# Get-PSWebHostRoleAssignment Function Added

**Date:** 2026-01-16

## Summary

Added `Get-PSWebHostRoleAssignment` function to the PSWebHost_Authentication module with comprehensive filtering options.

## Function Location

**File:** `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1`
**Lines:** 927-1032

## Features

### Parameters

- **`-ListAll`** - Lists all role assignments in the system
- **`-UserID`** - Filter by specific UserID (also accepts Email as UserID)
- **`-Email`** - Filter by user email address
- **`-Role`** - Filter by specific role name
- **Combinations** - Can combine UserID/Email with Role for specific lookups

### Parameter Sets

The function uses PowerShell parameter sets to provide a clean interface:
- `ListAll` - No filtering
- `ByUser` - Filter by UserID only
- `ByEmail` - Filter by Email only
- `ByRole` - Filter by Role only
- `ByUserAndRole` - Combine UserID and Role
- `ByEmailAndRole` - Combine Email and Role

## Usage Examples

### List All Role Assignments
```powershell
Get-PSWebHostRoleAssignment -ListAll
```

### Get Roles for Specific User (by ID)
```powershell
Get-PSWebHostRoleAssignment -UserID "025b86f6-bbc4-40ba-a38a-e49c8013844e"
```

### Get Roles for Specific User (by Email)
```powershell
Get-PSWebHostRoleAssignment -Email "test@localhost"
```

### Find All Users with Specific Role
```powershell
Get-PSWebHostRoleAssignment -Role "system_admin"
```

### Check if Specific User Has Specific Role
```powershell
Get-PSWebHostRoleAssignment -UserID "test@localhost" -Role "system_admin"
```

### Check Using Email and Role
```powershell
Get-PSWebHostRoleAssignment -Email "test@localhost" -Role "admin"
```

## Output Format

The function returns PSCustomObjects with the following properties:

```powershell
PrincipalID    # The ID stored in the roles table (can be UserID or Email)
Email          # User's email address (from PSWeb_Users join)
UserGUID       # User's GUID from PSWeb_Users table
PrincipalType  # Type of principal (usually 'user')
RoleName       # The assigned role name
```

## Implementation Details

### Query Logic

The function uses a LEFT JOIN between `PSWeb_Roles` and `PSWeb_Users` tables to:
1. Match PrincipalID to either User ID or Email
2. Return user information alongside role assignments
3. Support filtering by any combination of UserID, Email, or Role

### Case-Insensitive Matching

All string comparisons use `COLLATE NOCASE` for case-insensitive matching.

### SQL Injection Protection

All user inputs are sanitized using `Sanitize-SqlQueryString` before being included in queries.

## Related Functions

- `Add-PSWebHostRoleAssignment` - Adds a role to a user
- `Remove-PSWebHostRoleAssignment` - Removes a role from a user

---

## Menu Search Issue Resolution

### Current Status

The user `test@localhost` (ID: 025b86f6-bbc4-40ba-a38a-e49c8013844e) now has the `system_admin` role assigned in the database.

### To Fix Menu Search

**The user needs to log out and log back in** to refresh their session and pick up the new `system_admin` role.

**Steps:**
1. Log out of the browser session
2. Log back in with the same credentials
3. The session will now include the `system_admin` role
4. Search for "task" should now show "Task Management" in results

### Verification

After logging back in, verify the role is loaded:
```powershell
# Check role assignment in database
Get-PSWebHostRoleAssignment -Email "test@localhost"

# After login, check the session (in browser console or server logs)
# Session should contain: Roles: [..., "system_admin", ...]
```

### Alternative: Force Session Refresh

If logout/login doesn't work, the session might be cached. Options:
1. Clear browser cookies/session storage
2. Use incognito/private browsing mode
3. Restart the PSWebHost server to clear server-side session cache

---

**Status:** ✅ Function Added
**Testing:** Ready for use
**Documentation:** Complete
