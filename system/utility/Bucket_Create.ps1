#Requires -Version 7

<#
.SYNOPSIS
    Creates a new shared bucket with automatic group creation.

.DESCRIPTION
    Creates a new bucket with:
    - Unique name validation
    - Three auto-created groups (Owners, Writers, Readers)
    - Creator automatically added to Owners group
    - Filesystem folder creation

.PARAMETER BucketName
    User-friendly bucket name (must be unique)

.PARAMETER OwnerUserID
    User ID of the bucket creator/owner

.PARAMETER Description
    Optional bucket description

.PARAMETER InitialMembers
    Hashtable with initial group members:
    @{
        Owners = @("user1@example.com")
        Writers = @("user2@example.com", "user3@example.com")
        Readers = @("user4@example.com")
    }

.OUTPUTS
    Returns hashtable with:
    - Success: Boolean
    - BucketID: Created bucket ID (GUID)
    - Message: Status message
    - Bucket: Bucket details including group IDs

.EXAMPLE
    $result = & $script -BucketName "Marketing Files" -OwnerUserID "admin@example.com" -Description "Team marketing resources"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,

    [Parameter(Mandatory=$true)]
    [string]$OwnerUserID,

    [string]$Description = "",

    [hashtable]$InitialMembers = @{}
)

# Validate bucket name
if ($BucketName -notmatch '^[a-zA-Z0-9\s\-_]+$') {
    return @{
        Success = $false
        Message = "Bucket name can only contain letters, numbers, spaces, hyphens, and underscores"
    }
}

if ($BucketName.Length -gt 64) {
    return @{
        Success = $false
        Message = "Bucket name must be 64 characters or less"
    }
}

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

    # Sanitize inputs
    $safeName = $BucketName -replace "'", "''"
    $safeDesc = $Description -replace "'", "''"
    $safeOwnerID = $OwnerUserID -replace "'", "''"

    # Check if bucket name already exists
    $checkQuery = "SELECT BucketID FROM Shared_Buckets WHERE Name COLLATE NOCASE = '$safeName';"
    $existing = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

    if ($existing) {
        return @{
            Success = $false
            Message = "A bucket with this name already exists"
        }
    }

    # Generate bucket ID
    $bucketId = [Guid]::NewGuid().ToString()
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Create three groups
    $ownerGroupName = "$BucketName - Owners"
    $readGroupName = "$BucketName - Readers"
    $writeGroupName = "$BucketName - Writers"

    # Create Owner Group
    $ownerGroupId = [Guid]::NewGuid().ToString()
    $createOwnerGroup = @"
INSERT INTO User_Groups (GroupID, Name, OwnerUserID, GroupType, Created, Updated)
VALUES ('$ownerGroupId', '$ownerGroupName', '$safeOwnerID', 'bucket-owner', '$timestamp', '$timestamp');
"@
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $createOwnerGroup

    # Create Read Group
    $readGroupId = [Guid]::NewGuid().ToString()
    $createReadGroup = @"
INSERT INTO User_Groups (GroupID, Name, OwnerUserID, GroupType, Created, Updated)
VALUES ('$readGroupId', '$readGroupName', '$safeOwnerID', 'bucket-read', '$timestamp', '$timestamp');
"@
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $createReadGroup

    # Create Write Group
    $writeGroupId = [Guid]::NewGuid().ToString()
    $createWriteGroup = @"
INSERT INTO User_Groups (GroupID, Name, OwnerUserID, GroupType, Created, Updated)
VALUES ('$writeGroupId', '$writeGroupName', '$safeOwnerID', 'bucket-write', '$timestamp', '$timestamp');
"@
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $createWriteGroup

    # Create bucket record
    $createBucket = @"
INSERT INTO Shared_Buckets (BucketID, Name, Description, OwnerUserID, OwnerGroupID, ReadGroupID, WriteGroupID, Created, Updated)
VALUES ('$bucketId', '$safeName', '$safeDesc', '$safeOwnerID', '$ownerGroupId', '$readGroupId', '$writeGroupId', '$timestamp', '$timestamp');
"@
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $createBucket

    # Add creator to Owner group
    $addCreatorToOwners = @"
INSERT INTO User_Groups_Map (UserID, GroupID)
VALUES ('$safeOwnerID', '$ownerGroupId');
"@
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $addCreatorToOwners

    # Add initial members if provided
    if ($InitialMembers.Owners) {
        foreach ($memberEmail in $InitialMembers.Owners) {
            if ($memberEmail -ne $OwnerUserID) {
                $safeMember = $memberEmail -replace "'", "''"
                $addMember = "INSERT OR IGNORE INTO User_Groups_Map (UserID, GroupID) VALUES ('$safeMember', '$ownerGroupId');"
                Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $addMember
            }
        }
    }

    if ($InitialMembers.Writers) {
        foreach ($memberEmail in $InitialMembers.Writers) {
            $safeMember = $memberEmail -replace "'", "''"
            $addMember = "INSERT OR IGNORE INTO User_Groups_Map (UserID, GroupID) VALUES ('$safeMember', '$writeGroupId');"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $addMember
        }
    }

    if ($InitialMembers.Readers) {
        foreach ($memberEmail in $InitialMembers.Readers) {
            $safeMember = $memberEmail -replace "'", "''"
            $addMember = "INSERT OR IGNORE INTO User_Groups_Map (UserID, GroupID) VALUES ('$safeMember', '$readGroupId');"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $addMember
        }
    }

    # Create filesystem folder
    $bucketPath = Join-Path $projectRoot "PsWebHost_Data\SharedBuckets\$bucketId"
    New-Item -Path $bucketPath -ItemType Directory -Force | Out-Null

    # Log bucket creation
    Write-PSWebHostLog -Severity 'Info' -Category 'Buckets' `
        -Message "Bucket created: $BucketName" `
        -Data @{
            BucketID = $bucketId
            OwnerUserID = $OwnerUserID
            OwnerGroupID = $ownerGroupId
            ReadGroupID = $readGroupId
            WriteGroupID = $writeGroupId
        }

    return @{
        Success = $true
        BucketID = $bucketId
        Message = "Bucket created successfully"
        Bucket = @{
            BucketID = $bucketId
            Name = $BucketName
            Description = $Description
            OwnerUserID = $OwnerUserID
            OwnerGroupID = $ownerGroupId
            ReadGroupID = $readGroupId
            WriteGroupID = $writeGroupId
            Created = $timestamp
            Updated = $timestamp
            Path = $bucketPath
        }
    }
}
catch {
    Write-Error "Error creating bucket: $_"
    return @{
        Success = $false
        Message = "Error creating bucket: $($_.Exception.Message)"
    }
}
