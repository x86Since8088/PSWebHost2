# Groups_New.ps1
# Creates a new user group

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$GroupName,

    [Parameter(Mandatory=$false)]
    [string]$Description
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Groups_New.ps1]'

# Check if group already exists
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
$safeGroupName = Sanitize-SqlQueryString -String $GroupName
$checkQuery = "SELECT * FROM User_Groups WHERE Name = '$safeGroupName';"
$existingGroup = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if ($existingGroup) {
    throw "Group '$GroupName' already exists (GroupID: $($existingGroup.GroupID))"
}

# Generate GroupID
$groupID = [Guid]::NewGuid().ToString()
$created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

# Build insert query
$columns = @('GroupID', 'Name', 'Created', 'Updated')
$values = @(
    "'$groupID'",
    "'$safeGroupName'",
    "'$created'",
    "'$created'"
)

$query = "INSERT INTO User_Groups ($($columns -join ', ')) VALUES ($($values -join ', '));"

Write-Verbose "$MyTag Creating group: $GroupName"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query

# Store description if provided
if ($Description) {
    $dataQuery = @"
INSERT INTO User_Data (ID, Name, Data)
VALUES ('$groupID', 'Description', '$(Sanitize-SqlQueryString -String $Description)');
"@
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $dataQuery
}

Write-Verbose "$MyTag Group created successfully with GroupID: $groupID"

# Return the created group
$createdGroup = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM User_Groups WHERE GroupID = '$groupID';"

if ($Description) {
    $createdGroup | Add-Member -NotePropertyName Description -NotePropertyValue $Description
}

return $createdGroup
