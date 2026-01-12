# RoleAssignment_Remove.ps1
# Removes a role assignment with enhanced safety features

<#
.SYNOPSIS
    Removes a role assignment from a user or group.

.DESCRIPTION
    Removes a role assignment from the database. Supports removal by PrincipalID,
    email, or removing all assignments for a specific role. Includes safety
    confirmations and batch operations.

.PARAMETER PrincipalID
    The UserID or GroupID to remove the role from.

.PARAMETER Email
    The email address of the user to remove the role from.

.PARAMETER RoleName
    The name of the role to remove.

.PARAMETER RemoveAll
    When combined with -RoleName, removes the role from all principals.

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER WhatIf
    Show what would be removed without actually removing it.

.EXAMPLE
    .\RoleAssignment_Remove.ps1 -PrincipalID '6ec71a85-fb79-4ebc-aa1d-587c7f8b403c' -RoleName 'Debug'

    Removes the Debug role from the specified user (with confirmation).

.EXAMPLE
    .\RoleAssignment_Remove.ps1 -Email 'test@localhost' -RoleName 'Admin' -Force

    Removes the Admin role from the user without confirmation.

.EXAMPLE
    .\RoleAssignment_Remove.ps1 -RoleName 'OldRole' -RemoveAll -Force

    Removes the 'OldRole' role from all users and groups.

.EXAMPLE
    .\RoleAssignment_Remove.ps1 -Email 'test@localhost' -RoleName 'Debug' -WhatIf

    Shows what would be removed without actually removing it.
#>

[CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName='ByID')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='ByID')]
    [string]$PrincipalID,

    [Parameter(Mandatory=$true, ParameterSetName='ByEmail')]
    [string]$Email,

    [Parameter(Mandatory=$true)]
    [string]$RoleName,

    [Parameter(ParameterSetName='RemoveAll')]
    [switch]$RemoveAll,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[RoleAssignment_Remove.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

if ($Force) {
    $ConfirmPreference = 'None'
}

# Handle RemoveAll mode
if ($RemoveAll) {
    $safeRoleName = Sanitize-SqlQueryString -String $RoleName
    $assignments = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM PSWeb_Roles WHERE RoleName = '$safeRoleName';"

    if (-not $assignments) {
        Write-Host "No assignments found for role '$RoleName'" -ForegroundColor Yellow
        return
    }

    $count = @($assignments).Count
    Write-Warning "This will remove role '$RoleName' from $count principal(s)"

    if ($PSCmdlet.ShouldProcess("Remove role '$RoleName' from $count principal(s)", "Role Assignments", "Remove All")) {
        $deleteQuery = "DELETE FROM PSWeb_Roles WHERE RoleName = '$safeRoleName';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery
        Write-Host "✓ Removed role '$RoleName' from $count principal(s)" -ForegroundColor Green
    }
    return
}

# Resolve email to PrincipalID if specified
if ($PSCmdlet.ParameterSetName -eq 'ByEmail') {
    $safeEmail = Sanitize-SqlQueryString -String $Email
    $user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID, Email FROM Users WHERE Email COLLATE NOCASE = '$safeEmail';"
    if (-not $user) {
        throw "User with email '$Email' not found"
    }
    $PrincipalID = $user.UserID
    Write-Verbose "$MyTag Resolved email '$Email' to UserID '$PrincipalID'"
}

# Verify role assignment exists
$safePrincipalID = Sanitize-SqlQueryString -String $PrincipalID
$safeRoleName = Sanitize-SqlQueryString -String $RoleName

$checkQuery = "SELECT * FROM PSWeb_Roles WHERE PrincipalID COLLATE NOCASE = '$safePrincipalID' AND RoleName = '$safeRoleName';"
$roleAssignment = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if (-not $roleAssignment) {
    Write-Host "Role assignment not found (PrincipalID: $PrincipalID, RoleName: $RoleName)" -ForegroundColor Yellow
    return
}

# Get principal name for display
if ($roleAssignment.PrincipalType -eq 'User') {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email FROM Users WHERE UserID COLLATE NOCASE = '$safePrincipalID';"
    $principalName = if ($principal) { $principal.Email } else { $PrincipalID }
} else {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Name FROM User_Groups WHERE GroupID COLLATE NOCASE = '$safePrincipalID';"
    $principalName = if ($principal) { $principal.Name } else { $PrincipalID }
}

if ($PSCmdlet.ShouldProcess("Remove role '$RoleName' from $($roleAssignment.PrincipalType) '$principalName'", "Role Assignment", "Remove")) {
    $deleteQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID COLLATE NOCASE = '$safePrincipalID' AND RoleName = '$safeRoleName';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery

    Write-Host "✓ Role '$RoleName' removed from $($roleAssignment.PrincipalType) '$principalName'" -ForegroundColor Green
}
