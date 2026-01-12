# Groups_RemoveUser.ps1
# Removes a user from a group

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)]
    [string]$UserID,

    [Parameter(Mandatory=$true)]
    [string]$GroupID,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Groups_RemoveUser.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Verify mapping exists
$safeUserID = Sanitize-SqlQueryString -String $UserID
$safeGroupID = Sanitize-SqlQueryString -String $GroupID

$user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM Users WHERE UserID COLLATE NOCASE = '$safeUserID';"
$group = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM User_Groups WHERE GroupID COLLATE NOCASE = '$safeGroupID';"

if (-not $user) {
    throw "User with UserID '$UserID' not found"
}
if (-not $group) {
    throw "Group with GroupID '$GroupID' not found"
}

$checkQuery = "SELECT * FROM User_Groups_Map WHERE UserID COLLATE NOCASE = '$safeUserID' AND GroupID COLLATE NOCASE = '$safeGroupID';"
$mapping = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if (-not $mapping) {
    Write-Warning "User '$($user.Email)' is not a member of group '$($group.Name)'"
    return
}

if ($Force) {
    $ConfirmPreference = 'None'
}

if ($PSCmdlet.ShouldProcess("Remove user '$($user.Email)' from group '$($group.Name)'", "User-Group Mapping", "Remove")) {
    $deleteQuery = "DELETE FROM User_Groups_Map WHERE UserID COLLATE NOCASE = '$safeUserID' AND GroupID COLLATE NOCASE = '$safeGroupID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteQuery

    # Update group's Updated timestamp
    $updated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $updateGroupQuery = "UPDATE User_Groups SET Updated = '$updated' WHERE GroupID COLLATE NOCASE = '$safeGroupID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $updateGroupQuery

    Write-Verbose "$MyTag User '$($user.Email)' removed from group '$($group.Name)'"
    Write-Host "User removed from group successfully" -ForegroundColor Green
}
