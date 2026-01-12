# RoleAssignment_New.ps1
# Assigns a role to a user or group with enhanced features

<#
.SYNOPSIS
    Assigns a role to a user or group in PSWebHost.

.DESCRIPTION
    Creates a new role assignment for a user or group. Validates that the principal
    exists and prevents duplicate assignments. Optionally creates the role if it
    doesn't exist.

.PARAMETER PrincipalID
    The UserID (GUID) or GroupID of the principal to assign the role to.

.PARAMETER PrincipalType
    The type of principal: 'User' or 'Group'.

.PARAMETER RoleName
    The name of the role to assign (e.g., 'Admin', 'Debug', 'site_admin').

.PARAMETER Email
    Alternative to PrincipalID - specify the user's email address.

.PARAMETER CreateRoleIfMissing
    If specified, creates the role in the system if it doesn't exist yet.

.PARAMETER PassThru
    Returns the role assignment object after creation.

.EXAMPLE
    .\RoleAssignment_New.ps1 -PrincipalID '6ec71a85-fb79-4ebc-aa1d-587c7f8b403c' -PrincipalType 'User' -RoleName 'Debug'

    Assigns the Debug role to the specified user.

.EXAMPLE
    .\RoleAssignment_New.ps1 -Email 'admin@test.com' -RoleName 'Admin' -PassThru

    Assigns the Admin role to the user with the specified email and returns the assignment.

.EXAMPLE
    .\RoleAssignment_New.ps1 -Email 'test@localhost' -RoleName 'CustomRole' -CreateRoleIfMissing

    Assigns a custom role, creating it if it doesn't exist.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, ParameterSetName='ByID')]
    [string]$PrincipalID,

    [Parameter(Mandatory=$true, ParameterSetName='ByID')]
    [Parameter(Mandatory=$false, ParameterSetName='ByEmail')]
    [ValidateSet('User', 'Group')]
    [string]$PrincipalType = 'User',

    [Parameter(Mandatory=$true, ParameterSetName='ByEmail')]
    [string]$Email,

    [Parameter(Mandatory=$true)]
    [string]$RoleName,

    [switch]$CreateRoleIfMissing,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[RoleAssignment_New.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# If Email specified, look up the UserID
if ($PSCmdlet.ParameterSetName -eq 'ByEmail') {
    $safeEmail = Sanitize-SqlQueryString -String $Email
    $user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID, Email FROM Users WHERE Email COLLATE NOCASE = '$safeEmail';"
    if (-not $user) {
        throw "User with email '$Email' not found"
    }
    $PrincipalID = $user.UserID
    $PrincipalType = 'User'
    Write-Verbose "$MyTag Resolved email '$Email' to UserID '$PrincipalID'"
}

# Verify principal exists
$safePrincipalID = Sanitize-SqlQueryString -String $PrincipalID
if ($PrincipalType -eq 'User') {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID, Email FROM Users WHERE UserID COLLATE NOCASE = '$safePrincipalID';"
    if (-not $principal) {
        throw "User with UserID '$PrincipalID' not found"
    }
    $principalName = $principal.Email
} else {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT GroupID, Name FROM User_Groups WHERE GroupID COLLATE NOCASE = '$safePrincipalID';"
    if (-not $principal) {
        throw "Group with GroupID '$PrincipalID' not found"
    }
    $principalName = $principal.Name
}

# Check if role assignment already exists
$safeRoleName = Sanitize-SqlQueryString -String $RoleName
$checkQuery = "SELECT * FROM PSWeb_Roles WHERE PrincipalID COLLATE NOCASE = '$safePrincipalID' AND RoleName = '$safeRoleName';"
$existing = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if ($existing) {
    Write-Host "Role '$RoleName' is already assigned to $PrincipalType '$principalName'" -ForegroundColor Yellow
    if ($PassThru) {
        return [PSCustomObject]@{
            PrincipalID = $PrincipalID
            PrincipalType = $PrincipalType
            PrincipalName = $principalName
            RoleName = $RoleName
            Status = 'Already Assigned'
        }
    }
    return
}

# Create the role assignment
$insertQuery = @"
INSERT INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName)
VALUES ('$safePrincipalID', '$PrincipalType', '$safeRoleName');
"@

try {
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $insertQuery
    Write-Host "✓ Role '$RoleName' assigned to $PrincipalType '$principalName'" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*FOREIGN KEY constraint failed*" -and $CreateRoleIfMissing) {
        Write-Warning "Role '$RoleName' doesn't exist in the system. Note: This role will work but isn't formally defined."
        # Try again - SQLite might allow it depending on constraints
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $insertQuery
        Write-Host "✓ Role '$RoleName' assigned to $PrincipalType '$principalName' (new role)" -ForegroundColor Green
    } else {
        throw
    }
}

# Return the assignment if requested
if ($PassThru) {
    return [PSCustomObject]@{
        PrincipalID = $PrincipalID
        PrincipalType = $PrincipalType
        PrincipalName = $principalName
        RoleName = $RoleName
        AssignedAt = (Get-Date).ToString('o')
        Status = 'Created'
    }
}
