# RoleAssignment_Get.ps1
# Retrieves role assignments with flexible query options

<#
.SYNOPSIS
    Retrieves role assignments from PSWebHost database.

.DESCRIPTION
    Queries role assignments with multiple filter options. Can retrieve by user,
    by role, by email, or list all assignments. Supports group expansion and
    formatted output.

.PARAMETER PrincipalID
    Get roles for a specific principal (user or group) by ID.

.PARAMETER Email
    Get roles for a user by their email address.

.PARAMETER RoleName
    Get all principals that have a specific role.

.PARAMETER UserID
    Get roles for a specific user by UserID.

.PARAMETER ListAll
    List all role assignments in the system.

.PARAMETER ListRoles
    List all unique role names defined in the system.

.PARAMETER ExpandGroups
    Include roles inherited from group memberships.

.PARAMETER Format
    Output format: 'Table', 'List', 'Json', or 'Simple'. Default is 'Table'.

.EXAMPLE
    .\RoleAssignment_Get.ps1 -Email 'admin@test.com'

    Get all roles assigned to the user with email admin@test.com.

.EXAMPLE
    .\RoleAssignment_Get.ps1 -RoleName 'Debug'

    Get all users and groups that have the Debug role.

.EXAMPLE
    .\RoleAssignment_Get.ps1 -Email 'test@localhost' -ExpandGroups

    Get all roles for the user, including those from group memberships.

.EXAMPLE
    .\RoleAssignment_Get.ps1 -ListAll -Format Json

    Export all role assignments as JSON.

.EXAMPLE
    .\RoleAssignment_Get.ps1 -ListRoles

    List all unique role names in the system.
#>

[CmdletBinding(DefaultParameterSetName='ByPrincipal')]
param(
    [Parameter(ParameterSetName='ByPrincipal')]
    [string]$PrincipalID,

    [Parameter(ParameterSetName='ByEmail')]
    [string]$Email,

    [Parameter(ParameterSetName='ByRole')]
    [string]$RoleName,

    [Parameter(ParameterSetName='ByUser')]
    [string]$UserID,

    [Parameter(ParameterSetName='ListAll')]
    [switch]$ListAll,

    [Parameter(ParameterSetName='ListRoles')]
    [switch]$ListRoles,

    [Parameter(ParameterSetName='ByUser')]
    [Parameter(ParameterSetName='ByEmail')]
    [switch]$ExpandGroups,

    [ValidateSet('Table', 'List', 'Json', 'Simple')]
    [string]$Format = 'Table'
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[RoleAssignment_Get.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Resolve email to UserID if specified
if ($PSCmdlet.ParameterSetName -eq 'ByEmail') {
    $safeEmail = Sanitize-SqlQueryString -String $Email
    $user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID, Email FROM Users WHERE Email = '$safeEmail';"
    if (-not $user) {
        throw "User with email '$Email' not found"
    }
    $UserID = $user.UserID
    Write-Verbose "$MyTag Resolved email '$Email' to UserID '$UserID'"
}

# Build query based on parameter set
if ($PSCmdlet.ParameterSetName -eq 'ByPrincipal') {
    if ([string]::IsNullOrEmpty($PrincipalID)) {
        throw "PrincipalID parameter is required for this parameter set"
    }
    $safePrincipalID = Sanitize-SqlQueryString -String $PrincipalID
    $query = "SELECT * FROM PSWeb_Roles WHERE PrincipalID = '$safePrincipalID';"
}
elseif ($PSCmdlet.ParameterSetName -eq 'ByRole') {
    if ([string]::IsNullOrEmpty($RoleName)) {
        throw "RoleName parameter is required for this parameter set"
    }
    $safeRoleName = Sanitize-SqlQueryString -String $RoleName
    $query = "SELECT * FROM PSWeb_Roles WHERE RoleName = '$safeRoleName';"
}
elseif ($PSCmdlet.ParameterSetName -eq 'ByUser' -or $PSCmdlet.ParameterSetName -eq 'ByEmail') {
    if ([string]::IsNullOrEmpty($UserID)) {
        throw "UserID parameter is required for this parameter set"
    }
    $safeUserID = Sanitize-SqlQueryString -String $UserID

    if ($ExpandGroups) {
        # Get roles from direct assignment AND from groups the user is in
        $query = @"
SELECT DISTINCT r.PrincipalID, r.PrincipalType, r.RoleName, 'Direct' as Source
FROM PSWeb_Roles r
WHERE r.PrincipalID = '$safeUserID' AND r.PrincipalType = 'User'
UNION
SELECT DISTINCT r.PrincipalID, r.PrincipalType, r.RoleName, g.Name as Source
FROM PSWeb_Roles r
INNER JOIN User_Groups_Map ugm ON r.PrincipalID = ugm.GroupID
INNER JOIN User_Groups g ON ugm.GroupID = g.GroupID
WHERE ugm.UserID = '$safeUserID' AND r.PrincipalType = 'Group'
ORDER BY RoleName;
"@
    } else {
        # Only direct user role assignments
        $query = "SELECT * FROM PSWeb_Roles WHERE PrincipalID = '$safeUserID' AND PrincipalType = 'User';"
    }
}
elseif ($ListRoles) {
    # List all unique role names
    $query = "SELECT DISTINCT RoleName FROM PSWeb_Roles ORDER BY RoleName;"
}
elseif ($ListAll) {
    $query = "SELECT * FROM PSWeb_Roles ORDER BY RoleName, PrincipalType, PrincipalID;"
}
else {
    throw "No valid parameter set specified"
}

Write-Verbose "$MyTag Executing query: $query"
$roles = Get-PSWebSQLiteData -File $dbFile -Query $query

# Enrich with principal names
if ($roles -and -not $ListRoles) {
    foreach ($role in $roles) {
        if ($role.PSObject.Properties.Name -contains 'PrincipalID') {
            if ($role.PrincipalType -eq 'User') {
                $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email FROM Users WHERE UserID = '$($role.PrincipalID)';"
                if ($principal) {
                    $role | Add-Member -NotePropertyName PrincipalName -NotePropertyValue $principal.Email -Force
                }
            } elseif ($role.PrincipalType -eq 'Group') {
                $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Name FROM User_Groups WHERE GroupID = '$($role.PrincipalID)';"
                if ($principal) {
                    $role | Add-Member -NotePropertyName PrincipalName -NotePropertyValue $principal.Name -Force
                }
            }
        }
    }
}

# Format output
if (-not $roles) {
    Write-Host "No role assignments found." -ForegroundColor Yellow
    return
}

switch ($Format) {
    'Json' {
        return $roles | ConvertTo-Json -Depth 5
    }
    'List' {
        return $roles | Format-List
    }
    'Simple' {
        if ($ListRoles) {
            return $roles.RoleName
        } else {
            return $roles | Select-Object RoleName, PrincipalType, PrincipalName
        }
    }
    'Table' {
        if ($ListRoles) {
            Write-Host "`nAvailable Roles:" -ForegroundColor Cyan
            Write-Host "================" -ForegroundColor Cyan
            $roles | ForEach-Object { Write-Host "  • $($_.RoleName)" }
        } else {
            return $roles | Format-Table -Property RoleName, PrincipalType, PrincipalName, Source -AutoSize
        }
    }
}
