# Roles_Remove.ps1
# Removes a role assignment from a user or group

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$PrincipalID,

    [Parameter(Mandatory=$true)]
    [string]$RoleName,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Roles_Remove.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Verify role assignment exists
$safePrincipalID = Sanitize-SqlQueryString -String $PrincipalID
$safeRoleName = Sanitize-SqlQueryString -String $RoleName

$checkQuery = "SELECT * FROM PSWeb_Roles WHERE PrincipalID = '$safePrincipalID' AND RoleName = '$safeRoleName';"
$roleAssignment = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if (-not $roleAssignment) {
    throw "Role assignment not found (PrincipalID: $PrincipalID, RoleName: $RoleName)"
}

# Get principal name for display
if ($roleAssignment.PrincipalType -eq 'User') {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email FROM Users WHERE UserID = '$safePrincipalID';"
    $principalName = $principal.Email
} else {
    $principal = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Name FROM User_Groups WHERE GroupID = '$safePrincipalID';"
    $principalName = $principal.Name
}

if ($Force) {
    $ConfirmPreference = 'None'
}

if ($PSCmdlet.ShouldProcess("Remove role '$RoleName' from $($roleAssignment.PrincipalType) '$principalName'", "Role Assignment", "Remove")) {
    $deleteQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safePrincipalID' AND RoleName = '$safeRoleName';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery

    Write-Verbose "$MyTag Role '$RoleName' removed from $($roleAssignment.PrincipalType) '$principalName'"
    Write-Host "Role assignment removed successfully" -ForegroundColor Green
}
