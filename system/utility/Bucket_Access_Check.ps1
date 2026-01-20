#Requires -Version 7

<#
.SYNOPSIS
    Checks if a user has permission to access a bucket.

.DESCRIPTION
    Verifies user access to a shared bucket by checking group membership.
    Returns access level (owner/write/read) or null if no access.

.PARAMETER UserID
    The user ID to check (email or identifier)

.PARAMETER BucketID
    The bucket ID (GUID)

.PARAMETER RequiredPermission
    Required permission level: 'read', 'write', or 'owner'
    Default: 'read'

.OUTPUTS
    Returns a hashtable with:
    - HasAccess: Boolean indicating if user has required permission
    - AccessLevel: String ('owner', 'write', 'read', or $null)
    - Bucket: Hashtable with bucket details (if access granted)

.EXAMPLE
    $access = & $bucketAccessScript -UserID "user@example.com" -BucketID "abc-123" -RequiredPermission 'write'
    if ($access.HasAccess) {
        Write-Host "User has write access to bucket"
    }
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$UserID,

    [Parameter(Mandatory=$true)]
    [string]$BucketID,

    [ValidateSet('read', 'write', 'owner')]
    [string]$RequiredPermission = 'read'
)

# Initialize result
$result = @{
    HasAccess = $false
    AccessLevel = $null
    Bucket = $null
}

try {
    # Get database path
    $dbFile = if ($Global:PSWebServer.Project_Root.Path) {
        Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    } else {
        # Standalone execution
        $projectRoot = Split-Path (Split-Path $PSScriptRoot)
        Join-Path $projectRoot "PsWebHost_Data\pswebhost.db"
    }

    # Sanitize inputs
    $safeUserID = $UserID -replace "'", "''"
    $safeBucketID = $BucketID -replace "'", "''"

    # SQL query to check bucket access via group membership
    $query = @"
WITH UserGroups AS (
    SELECT GroupID
    FROM User_Groups_Map
    WHERE UserID COLLATE NOCASE = '$safeUserID'
)
SELECT
    CASE
        WHEN sb.OwnerGroupID IN (SELECT GroupID FROM UserGroups) THEN 'owner'
        WHEN sb.WriteGroupID IN (SELECT GroupID FROM UserGroups) THEN 'write'
        WHEN sb.ReadGroupID IN (SELECT GroupID FROM UserGroups) THEN 'read'
        ELSE NULL
    END AS AccessLevel,
    sb.BucketID,
    sb.Name,
    sb.Description,
    sb.OwnerUserID,
    sb.OwnerGroupID,
    sb.ReadGroupID,
    sb.WriteGroupID,
    sb.Created,
    sb.Updated
FROM Shared_Buckets sb
WHERE sb.BucketID COLLATE NOCASE = '$safeBucketID';
"@

    # Execute query
    $bucketData = Get-PSWebSQLiteData -File $dbFile -Query $query

    if ($bucketData -and $bucketData.AccessLevel) {
        # User has some level of access
        $accessLevel = $bucketData.AccessLevel

        # Check if access level meets requirements
        $permissionHierarchy = @{
            'owner' = 3
            'write' = 2
            'read' = 1
        }

        $userLevel = $permissionHierarchy[$accessLevel]
        $requiredLevel = $permissionHierarchy[$RequiredPermission]

        if ($userLevel -ge $requiredLevel) {
            $result.HasAccess = $true
        }

        $result.AccessLevel = $accessLevel
        $result.Bucket = @{
            BucketID = $bucketData.BucketID
            Name = $bucketData.Name
            Description = $bucketData.Description
            OwnerUserID = $bucketData.OwnerUserID
            OwnerGroupID = $bucketData.OwnerGroupID
            ReadGroupID = $bucketData.ReadGroupID
            WriteGroupID = $bucketData.WriteGroupID
            Created = $bucketData.Created
            Updated = $bucketData.Updated
        }
    }
}
catch {
    Write-Error "Error checking bucket access: $_"
}

return $result
