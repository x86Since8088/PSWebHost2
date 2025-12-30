# Groups_Remove.ps1
# Removes a user group and all associated mappings

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)]
    [string]$GroupID,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Groups_Remove.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Get group info
$safeGroupID = Sanitize-SqlQueryString -String $GroupID
$group = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM User_Groups WHERE GroupID = '$safeGroupID';"

if (-not $group) {
    throw "Group with GroupID '$GroupID' not found"
}

# Get member count
$memberCountQuery = "SELECT COUNT(*) as Count FROM User_Groups_Map WHERE GroupID = '$safeGroupID';"
$memberCount = (Get-PSWebSQLiteData -File $dbFile -Query $memberCountQuery).Count

# Get role count
$roleCountQuery = "SELECT COUNT(*) as Count FROM PSWeb_Roles WHERE PrincipalID = '$safeGroupID' AND PrincipalType = 'Group';"
$roleCount = (Get-PSWebSQLiteData -File $dbFile -Query $roleCountQuery).Count

Write-Verbose "$MyTag Group '$($group.Name)' has $memberCount members and $roleCount roles"

if ($Force) {
    $ConfirmPreference = 'None'
}

if ($PSCmdlet.ShouldProcess("Group '$($group.Name)' (GroupID: $GroupID, Members: $memberCount, Roles: $roleCount)", "Remove")) {

    # Remove user-group mappings
    $deleteMappingsQuery = "DELETE FROM User_Groups_Map WHERE GroupID = '$safeGroupID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteMappingsQuery
    Write-Verbose "$MyTag Removed $memberCount user-group mappings"

    # Remove roles assigned to this group
    $deleteRolesQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safeGroupID' AND PrincipalType = 'Group';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteRolesQuery
    Write-Verbose "$MyTag Removed $roleCount role assignments"

    # Remove group data
    $deleteDataQuery = "DELETE FROM User_Data WHERE ID = '$safeGroupID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteDataQuery

    # Remove the group itself
    $deleteGroupQuery = "DELETE FROM User_Groups WHERE GroupID = '$safeGroupID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteGroupQuery
    Write-Verbose "$MyTag Group '$($group.Name)' removed successfully"

    Write-Host "Group '$($group.Name)' removed successfully" -ForegroundColor Green
}
