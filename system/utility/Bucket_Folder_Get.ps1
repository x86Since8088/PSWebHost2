#Requires -Version 7

<#
.SYNOPSIS
    Gets the filesystem path for a bucket with permission validation.

.DESCRIPTION
    Returns the filesystem path to a shared bucket's folder after validating
    the user has the required permission level. Similar to UserData_Folder_Get.ps1
    but for bucket storage.

.PARAMETER BucketID
    The bucket ID (GUID)

.PARAMETER UserID
    The user ID requesting access

.PARAMETER RequiredPermission
    Required permission level: 'read', 'write', or 'owner'
    Default: 'read'

.PARAMETER CreateIfMissing
    Create the bucket folder if it doesn't exist
    Default: $true

.OUTPUTS
    Returns hashtable with:
    - Success: Boolean
    - Path: Filesystem path to bucket folder
    - AccessLevel: User's access level
    - Message: Status message (if error)

.EXAMPLE
    $result = & $script -BucketID "abc-123" -UserID "user@example.com" -RequiredPermission 'write'
    if ($result.Success) {
        $path = $result.Path
        # Perform file operations in $path
    }
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketID,

    [Parameter(Mandatory=$true)]
    [string]$UserID,

    [ValidateSet('read', 'write', 'owner')]
    [string]$RequiredPermission = 'read',

    [bool]$CreateIfMissing = $true
)

# Initialize result
$result = @{
    Success = $false
    Path = $null
    AccessLevel = $null
    Message = ""
}

try {
    # Get project root
    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        # Standalone execution
        Split-Path (Split-Path $PSScriptRoot)
    }

    # Check if user has required permission
    $accessCheckScript = Join-Path $PSScriptRoot "Bucket_Access_Check.ps1"
    $accessResult = & $accessCheckScript -UserID $UserID -BucketID $BucketID -RequiredPermission $RequiredPermission

    if (-not $accessResult.HasAccess) {
        $result.Message = "Access denied. User does not have '$RequiredPermission' permission for this bucket."
        return $result
    }

    # Get bucket folder path
    $bucketPath = Join-Path $projectRoot "PsWebHost_Data\SharedBuckets\$BucketID"

    # Create folder if it doesn't exist and CreateIfMissing is true
    if ($CreateIfMissing -and -not (Test-Path $bucketPath)) {
        New-Item -Path $bucketPath -ItemType Directory -Force | Out-Null
        Write-PSWebHostLog -Severity 'Info' -Category 'Buckets' `
            -Message "Created missing bucket folder: $BucketID" `
            -Data @{ BucketID = $BucketID; UserID = $UserID }
    }

    # Verify folder exists
    if (-not (Test-Path $bucketPath)) {
        $result.Message = "Bucket folder does not exist and CreateIfMissing is false"
        return $result
    }

    # Return success with path and access level
    $result.Success = $true
    $result.Path = $bucketPath
    $result.AccessLevel = $accessResult.AccessLevel

    return $result
}
catch {
    Write-Error "Error getting bucket folder: $_"
    $result.Message = "Error getting bucket folder: $($_.Exception.Message)"
    return $result
}
