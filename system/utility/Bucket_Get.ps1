#Requires -Version 7

<#
.SYNOPSIS
    Lists all buckets a user has access to.

.DESCRIPTION
    Retrieves all shared buckets where the user is a member of any permission group
    (Owner, Write, or Read). Returns bucket details along with the user's access level.

.PARAMETER UserID
    The user ID to check (email or identifier)

.OUTPUTS
    Returns array of hashtables with:
    - BucketID: Bucket GUID
    - Name: User-friendly bucket name
    - Description: Bucket description
    - OwnerUserID: Bucket creator/owner
    - AccessLevel: User's access ('owner', 'write', 'read')
    - Created: Creation timestamp
    - Updated: Last update timestamp

.EXAMPLE
    $buckets = & $script -UserID "user@example.com"
    foreach ($bucket in $buckets) {
        Write-Host "$($bucket.Name) - Access: $($bucket.AccessLevel)"
    }
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$UserID
)

try {
    # Get database path
    $dbFile = if ($Global:PSWebServer.Project_Root.Path) {
        Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    } else {
        # Standalone execution
        $projectRoot = Split-Path (Split-Path $PSScriptRoot)
        Join-Path $projectRoot "PsWebHost_Data\pswebhost.db"
    }

    # Sanitize input
    $safeUserID = $UserID -replace "'", "''"

    # SQL query to get all buckets user has access to
    # Uses CTE to find user's groups, then checks which buckets reference those groups
    $query = @"
WITH UserGroups AS (
    SELECT GroupID
    FROM User_Groups_Map
    WHERE UserID COLLATE NOCASE = '$safeUserID'
)
SELECT
    sb.BucketID,
    sb.Name,
    sb.Description,
    sb.OwnerUserID,
    sb.OwnerGroupID,
    sb.ReadGroupID,
    sb.WriteGroupID,
    sb.Created,
    sb.Updated,
    CASE
        WHEN sb.OwnerGroupID IN (SELECT GroupID FROM UserGroups) THEN 'owner'
        WHEN sb.WriteGroupID IN (SELECT GroupID FROM UserGroups) THEN 'write'
        WHEN sb.ReadGroupID IN (SELECT GroupID FROM UserGroups) THEN 'read'
        ELSE NULL
    END AS AccessLevel
FROM Shared_Buckets sb
WHERE sb.OwnerGroupID IN (SELECT GroupID FROM UserGroups)
   OR sb.WriteGroupID IN (SELECT GroupID FROM UserGroups)
   OR sb.ReadGroupID IN (SELECT GroupID FROM UserGroups)
ORDER BY sb.Name COLLATE NOCASE;
"@

    # Execute query
    $results = Get-PSWebSQLiteData -File $dbFile -Query $query

    # Convert results to array of hashtables
    $buckets = @()

    if ($results) {
        # Handle both single result and multiple results
        $resultArray = if ($results -is [array]) { $results } else { @($results) }

        foreach ($row in $resultArray) {
            $buckets += @{
                BucketID = $row.BucketID
                Name = $row.Name
                Description = $row.Description
                OwnerUserID = $row.OwnerUserID
                OwnerGroupID = $row.OwnerGroupID
                ReadGroupID = $row.ReadGroupID
                WriteGroupID = $row.WriteGroupID
                AccessLevel = $row.AccessLevel
                Created = $row.Created
                Updated = $row.Updated
            }
        }
    }

    return $buckets
}
catch {
    Write-Error "Error retrieving buckets: $_"
    return @()
}
