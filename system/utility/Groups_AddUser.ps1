# Groups_AddUser.ps1
# Adds a user to a group

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$UserID,

    [Parameter(Mandatory=$true)]
    [string]$GroupID
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Groups_AddUser.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Verify user exists
$safeUserID = Sanitize-SqlQueryString -String $UserID
$user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM Users WHERE UserID COLLATE NOCASE = '$safeUserID';"
if (-not $user) {
    throw "User with UserID '$UserID' not found"
}

# Verify group exists
$safeGroupID = Sanitize-SqlQueryString -String $GroupID
$group = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM User_Groups WHERE GroupID COLLATE NOCASE = '$safeGroupID';"
if (-not $group) {
    throw "Group with GroupID '$GroupID' not found"
}

# Check if mapping already exists
$checkQuery = "SELECT * FROM User_Groups_Map WHERE UserID COLLATE NOCASE = '$safeUserID' AND GroupID COLLATE NOCASE = '$safeGroupID';"
$existing = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if ($existing) {
    Write-Warning "User '$($user.Email)' is already a member of group '$($group.Name)'"
    return $existing
}

# Create the mapping
$insertQuery = "INSERT INTO User_Groups_Map (UserID, GroupID) VALUES ('$safeUserID', '$safeGroupID');"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $insertQuery

# Update group's Updated timestamp
$updated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$updateGroupQuery = "UPDATE User_Groups SET Updated = '$updated' WHERE GroupID COLLATE NOCASE = '$safeGroupID';"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $updateGroupQuery

Write-Verbose "$MyTag User '$($user.Email)' added to group '$($group.Name)'"

# Return the mapping
return [PSCustomObject]@{
    UserID = $UserID
    UserEmail = $user.Email
    GroupID = $GroupID
    GroupName = $group.Name
    Added = (Get-Date)
}
