# Role Assignment Quick Start Guide

## Interactive Menu (Easiest!)

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Menu.ps1'"
```

Opens an interactive menu with all role management options.

## Quick Commands

### Add Debug Role to Your Account

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_New.ps1' -Email 'your-email@test.com' -RoleName 'Debug'"
```

### View Your Roles

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -Email 'your-email@test.com'"
```

### List All Users

```powershell
pwsh -Command "Import-Module PSSQLite; Invoke-SqliteQuery -DataSource 'C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db' -Query 'SELECT Email FROM Users ORDER BY Email'"
```

### List All Roles

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Get.ps1' -ListRoles"
```

### Show Statistics

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_List.ps1' -ShowStatistics"
```

### Remove a Role

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Remove.ps1' -Email 'user@test.com' -RoleName 'OldRole' -Force"
```

### Add Multiple Roles at Once

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\RoleAssignment_Update.ps1' -Email 'admin@test.com' -AddRoles 'Admin','Debug','site_admin'"
```

## Available Scripts

| Script | Purpose |
|--------|---------|
| `RoleAssignment_Menu.ps1` | Interactive menu interface |
| `RoleAssignment_New.ps1` | Assign a role to a user/group |
| `RoleAssignment_Get.ps1` | Query role assignments |
| `RoleAssignment_Remove.ps1` | Remove role assignments |
| `RoleAssignment_List.ps1` | List all assignments with stats |
| `RoleAssignment_Update.ps1` | Bulk updates and sync |

## Common Roles

- `authenticated` - Basic authenticated user
- `Debug` - Developer/debug access (Admin Tools menu)
- `Admin` - Administrator (Admin Tools menu)
- `site_admin` - Site administrator (Site Admin menu)
- `system_admin` - System administrator (System Admin menu)

## See Full Documentation

```
C:\SC\PsWebHost\system\utility\ROLE_ASSIGNMENT_README.md
```
