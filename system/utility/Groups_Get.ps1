# Groups_Get.ps1
# Retrieves user groups from the database

[CmdletBinding(DefaultParameterSetName='GroupID')]
param(
    [Parameter(ParameterSetName='GroupID')]
    [string]$GroupID,

    [Parameter(ParameterSetName='GroupName')]
    [string]$GroupName,

    [Parameter(ParameterSetName='ListAll')]
    [switch]$ListAll,

    [Parameter(ParameterSetName='ByUser')]
    [string]$UserID
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Groups_Get.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

if ($PSCmdlet.ParameterSetName -eq 'GroupID') {
    if ([string]::IsNullOrEmpty($GroupID)) {
        throw "GroupID parameter is required for this parameter set"
    }
    $safeGroupID = Sanitize-SqlQueryString -String $GroupID
    $query = "SELECT * FROM User_Groups WHERE GroupID = '$safeGroupID';"
}
elseif ($PSCmdlet.ParameterSetName -eq 'GroupName') {
    if ([string]::IsNullOrEmpty($GroupName)) {
        throw "GroupName parameter is required for this parameter set"
    }
    $safeGroupName = Sanitize-SqlQueryString -String $GroupName
    $query = "SELECT * FROM User_Groups WHERE Name = '$safeGroupName';"
}
elseif ($PSCmdlet.ParameterSetName -eq 'ByUser') {
    if ([string]::IsNullOrEmpty($UserID)) {
        throw "UserID parameter is required for this parameter set"
    }
    $safeUserID = Sanitize-SqlQueryString -String $UserID
    $query = @"
SELECT g.* FROM User_Groups g
INNER JOIN User_Groups_Map ugm ON g.GroupID = ugm.GroupID
WHERE ugm.UserID = '$safeUserID';
"@
}
elseif ($ListAll) {
    $query = "SELECT * FROM User_Groups ORDER BY Name;"
}
else {
    throw "No valid parameter set specified"
}

Write-Verbose "$MyTag Executing query: $query"
$groups = Get-PSWebSQLiteData -File $dbFile -Query $query

if ($groups) {
    # Add member count to each group
    foreach ($group in $groups) {
        $countQuery = "SELECT COUNT(*) as MemberCount FROM User_Groups_Map WHERE GroupID = '$($group.GroupID)';"
        $count = Get-PSWebSQLiteData -File $dbFile -Query $countQuery
        $group | Add-Member -NotePropertyName MemberCount -NotePropertyValue $count.MemberCount

        # Get description if exists
        $descQuery = "SELECT Data FROM User_Data WHERE ID = '$($group.GroupID)' AND Name = 'Description';"
        $desc = Get-PSWebSQLiteData -File $dbFile -Query $descQuery
        if ($desc -and $desc.Data) {
            # Convert from bytes to string if needed
            if ($desc.Data -is [byte[]]) {
                $descString = [System.Text.Encoding]::UTF8.GetString($desc.Data)
            } else {
                $descString = $desc.Data
            }
            $group | Add-Member -NotePropertyName Description -NotePropertyValue $descString
        }
    }
}

return $groups
