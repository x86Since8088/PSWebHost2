# Roles_New.ps1
# Assigns a role to a user or group

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$PrincipalID,

    [Parameter(Mandatory=$true)]
    [ValidateSet('User', 'Group')]
    [string]$PrincipalType,

    [Parameter(Mandatory=$true)]
    [string]$RoleName
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Roles_New.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Verify principal exists
$safePrincipalID = Sanitize-SqlQueryString -String $PrincipalID
if ($PrincipalType -eq 'User') {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM Users WHERE UserID = '$safePrincipalID';"
    if (-not $principal) {
        throw "User with UserID '$PrincipalID' not found"
    }
    $principalName = $principal.Email
} else {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM User_Groups WHERE GroupID = '$safePrincipalID';"
    if (-not $principal) {
        throw "Group with GroupID '$PrincipalID' not found"
    }
    $principalName = $principal.Name
}

# Check if role assignment already exists
$safeRoleName = Sanitize-SqlQueryString -String $RoleName
$checkQuery = "SELECT * FROM PSWeb_Roles WHERE PrincipalID = '$safePrincipalID' AND RoleName = '$safeRoleName';"
$existing = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if ($existing) {
    Write-Warning "Role '$RoleName' is already assigned to $PrincipalType '$principalName'"
    return $existing
}

# Create the role assignment
$insertQuery = @"
INSERT INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName)
VALUES ('$safePrincipalID', '$PrincipalType', '$safeRoleName');
"@

Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $insertQuery
Write-Verbose "$MyTag Role '$RoleName' assigned to $PrincipalType '$principalName'"

# Return the assignment
return [PSCustomObject]@{
    PrincipalID = $PrincipalID
    PrincipalType = $PrincipalType
    PrincipalName = $principalName
    RoleName = $RoleName
    Assigned = (Get-Date)
}
