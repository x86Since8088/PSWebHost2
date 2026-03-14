# How to Access the Admin Tools Menu

## Current Status

Your menu is showing:
- ✅ Main Menu (World Map, Server Load, Real-time Events, File Explorer, System Log)
- ✅ Pending Review
- ✅ Not Implemented

**Missing**:
- ❌ Site Admin Menu
- ❌ System Admin Menu
- ❌ **Admin Tools** (includes Test Error)

This means your current user account doesn't have admin roles assigned.

## Solution: Add Admin Role to Your User

### Step 1: Find Your UserID

Run this command to list all users in the database:

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\Account_AuthProvider_Password_Get.ps1'"
```

Or query the database directly:

```powershell
pwsh -Command "
    Import-Module PSSQLite
    $db = 'C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db'
    Invoke-SqliteQuery -DataSource \$db -Query 'SELECT UserID, Email FROM Users'
"
```

**Look for your email** and note the `UserID` (a GUID like `6ec71a85-fb79-4ebc-aa1d-587c7f8b403c`)

### Step 2: Add the Debug Role

Once you have your UserID, run:

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\Roles_New.ps1' -PrincipalID 'YOUR-USER-ID-HERE' -PrincipalType 'User' -RoleName 'Debug'"
```

**Example**:
```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\Roles_New.ps1' -PrincipalID '6ec71a85-fb79-4ebc-aa1d-587c7f8b403c' -PrincipalType 'User' -RoleName 'Debug'"
```

### Step 3: Verify the Role Assignment

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\Roles_Get.ps1' -UserID 'YOUR-USER-ID-HERE'"
```

You should see output like:
```
PrincipalID   : 6ec71a85-fb79-4ebc-aa1d-587c7f8b403c
PrincipalType : User
RoleName      : Debug
PrincipalName : your-email@example.com
```

### Step 4: Refresh Your Browser

1. **Log out** if you're currently logged in (or clear cookies)
2. **Log back in** to get a new session with the updated roles
3. **Refresh** the SPA page (http://localhost:8080/spa)
4. **Check the left menu** - you should now see:

```
Main Menu
├── World Map
├── Server Load
├── Real-time Events
├── File Explorer
└── System Log

Admin Tools ← NEW!
├── Test Error Modals
├── Trigger Test Error
├── Debug Variables
└── Job Status
```

## Alternative: Use an Existing Admin Account

If you already have a user with admin privileges, simply log in with that account instead.

## Quick Test Without Role Assignment

If you just want to test the error modal system without role setup, you can:

**Access the demo page directly** (works for any user):
```
http://localhost:8080/public/error-modal-demo.html
```

This page is publicly accessible and demonstrates all three modal types.

## Available Roles

You can assign any of these roles to see different menu sections:

| Role | Menu Sections Visible |
|------|----------------------|
| `authenticated` | Main Menu only |
| `site_admin` | Main Menu + Site Admin Menu + Admin Tools |
| `system_admin` | Main Menu + System Admin Menu + Admin Tools |
| `Debug` | Main Menu + Admin Tools |
| `Admin` | Main Menu + Admin Tools |

## Troubleshooting

### "User not found"
- Double-check the UserID is correct (it's case-sensitive)
- Make sure you're using the UserID, not the email address

### "Role already assigned"
- This is fine! It means the role is already there
- Try logging out and back in

### Menu still not showing
- Clear browser cache and cookies
- Make sure you logged out and back in after adding the role
- Check browser console for any JavaScript errors

### Can't find any users
You might need to create a test user first:

```powershell
pwsh -Command "& 'C:\SC\PsWebHost\system\auth\New-TestUser.ps1' -Email 'admin@test.com' -Password 'TestPassword123!'"
```

Then follow Step 2 to add the Debug role to this new user.

## Summary

**Quick Commands** (replace YOUR-USER-ID with your actual UserID):

```powershell
# 1. List users
pwsh -Command "Import-Module PSSQLite; Invoke-SqliteQuery -DataSource 'C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db' -Query 'SELECT UserID, Email FROM Users'"

# 2. Add Debug role
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\Roles_New.ps1' -PrincipalID 'YOUR-USER-ID' -PrincipalType 'User' -RoleName 'Debug'"

# 3. Verify
pwsh -Command "& 'C:\SC\PsWebHost\system\utility\Roles_Get.ps1' -UserID 'YOUR-USER-ID'"

# 4. Log out, log in, refresh!
```

Once you have the Debug role, the "Admin Tools" menu will appear with all the error testing options!
