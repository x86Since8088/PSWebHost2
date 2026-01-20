#Requires -Version 7

<#
.SYNOPSIS
    Deletes a shared bucket (owner only).

.DESCRIPTION
    Deletes a bucket along with its three associated groups and filesystem folder.
    Only bucket owners can delete buckets. This operation is irreversible.

.PARAMETER BucketID
    The bucket ID (GUID) to delete

.PARAMETER UserID
    The user ID requesting deletion (must be bucket owner)

.OUTPUTS
    Returns hashtable with:
    - Success: Boolean
    - Message: Status message
    - DeletedBucket: Details of deleted bucket (if successful)

.EXAMPLE
    $result = & $script -BucketID "abc-123" -UserID "admin@example.com"
    if ($result.Success) {
        Write-Host "Bucket deleted successfully"
    }
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketID,

    [Parameter(Mandatory=$true)]
    [string]$UserID
)

try {
    # Get database and project paths
    $dbFile = if ($Global:PSWebServer.Project_Root.Path) {
        Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    } else {
        $projectRoot = Split-Path (Split-Path $PSScriptRoot)
        Join-Path $projectRoot "PsWebHost_Data\pswebhost.db"
    }

    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        Split-Path (Split-Path $PSScriptRoot)
    }

    # Check if user has owner permission
    $accessCheckScript = Join-Path $PSScriptRoot "Bucket_Access_Check.ps1"
    $accessResult = & $accessCheckScript -UserID $UserID -BucketID $BucketID -RequiredPermission 'owner'

    if (-not $accessResult.HasAccess) {
        return @{
            Success = $false
            Message = "Only bucket owners can delete buckets"
        }
    }

    # Get bucket details before deletion
    $bucket = $accessResult.Bucket

    # Sanitize inputs
    $safeBucketID = $BucketID -replace "'", "''"

    # Delete bucket record (foreign key CASCADE will delete Bucket_Access_Log entries)
    $deleteBucket = "DELETE FROM Shared_Buckets WHERE BucketID = '$safeBucketID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteBucket

    # Delete the three associated groups
    # Note: User_Groups_Map entries will CASCADE delete due to foreign key
    $ownerGroupId = $bucket.OwnerGroupID -replace "'", "''"
    $readGroupId = $bucket.ReadGroupID -replace "'", "''"
    $writeGroupId = $bucket.WriteGroupID -replace "'", "''"

    $deleteGroups = @"
DELETE FROM User_Groups WHERE GroupID = '$ownerGroupId';
DELETE FROM User_Groups WHERE GroupID = '$readGroupId';
DELETE FROM User_Groups WHERE GroupID = '$writeGroupId';
"@
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteGroups

    # Delete filesystem folder
    $bucketPath = Join-Path $projectRoot "PsWebHost_Data\SharedBuckets\$BucketID"
    if (Test-Path $bucketPath) {
        Remove-Item -Path $bucketPath -Recurse -Force
    }

    # Log bucket deletion
    Write-PSWebHostLog -Severity 'Info' -Category 'Buckets' `
        -Message "Bucket deleted: $($bucket.Name)" `
        -Data @{
            BucketID = $BucketID
            UserID = $UserID
            OwnerGroupID = $bucket.OwnerGroupID
            ReadGroupID = $bucket.ReadGroupID
            WriteGroupID = $bucket.WriteGroupID
        }

    return @{
        Success = $true
        Message = "Bucket deleted successfully"
        DeletedBucket = @{
            BucketID = $bucket.BucketID
            Name = $bucket.Name
            Description = $bucket.Description
            OwnerUserID = $bucket.OwnerUserID
        }
    }
}
catch {
    Write-Error "Error deleting bucket: $_"
    return @{
        Success = $false
        Message = "Error deleting bucket: $($_.Exception.Message)"
    }
}
