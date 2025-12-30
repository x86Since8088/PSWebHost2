# Roles_Get.ps1
# Retrieves role assignments from the database

[CmdletBinding(DefaultParameterSetName='ByPrincipal')]
param(
    [Parameter(ParameterSetName='ByPrincipal')]
    [string]$PrincipalID,

    [Parameter(ParameterSetName='ByRole')]
    [string]$RoleName,

    [Parameter(ParameterSetName='ListAll')]
    [switch]$ListAll,

    [Parameter(ParameterSetName='ListRoles')]
    [switch]$ListRoles,

    [Parameter(ParameterSetName='ByUser')]
    [string]$UserID,

    [switch]$ExpandGroups
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Roles_Get.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

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
elseif ($PSCmdlet.ParameterSetName -eq 'ByUser') {
    if ([string]::IsNullOrEmpty($UserID)) {
        throw "UserID parameter is required for this parameter set"
    }
    $safeUserID = Sanitize-SqlQueryString -String $UserID

    if ($ExpandGroups) {
        # Get roles from direct assignment AND from groups the user is in
        $query = @"
SELECT DISTINCT r.*, 'Direct' as Source FROM PSWeb_Roles r WHERE r.PrincipalID = '$safeUserID'
UNION
SELECT DISTINCT r.*, g.Name as Source FROM PSWeb_Roles r
INNER JOIN User_Groups_Map ugm ON r.PrincipalID = ugm.GroupID
INNER JOIN User_Groups g ON ugm.GroupID = g.GroupID
WHERE ugm.UserID = '$safeUserID' AND r.PrincipalType = 'Group';
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

if ($roles) {
    # Enrich with principal names
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

return $roles
