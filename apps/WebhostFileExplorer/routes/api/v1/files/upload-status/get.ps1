param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Get upload session status

.DESCRIPTION
    GET /api/v1/files/upload-status?guid=XXXX
    Returns upload session details including chunk bitmap, received bytes, and missing chunks

.EXAMPLE
    GET /api/v1/files/upload-status?guid=550e8400-e29b-41d4-a716-446655440000
    Response: {
        "status": "success",
        "data": {
            "guid": "550e8400-e29b-41d4-a716-446655440000",
            "fileName": "largefile.zip",
            "fileSize": 104857600,
            "chunkSize": 26214400,
            "totalChunks": 4,
            "receivedChunks": 2,
            "receivedBytes": 52428800,
            "chunkBitmap": [true, true, false, false],
            "missingChunks": [2, 3],
            "uploadMethod": "websocket",
            "startTime": 1706385600,
            "lastActivityTime": 1706385620,
            "uploadStatus": "active"
        }
    }
#>

# Import File Explorer helper module functions
try {
    Import-TrackedModule "FileExplorerHelper"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to import FileExplorerHelper module: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Validate session
$userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
if (-not $userID) { return }

# Get GUID from query string
$guid = $Request.QueryString['guid']
if (-not $guid) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required query parameter: guid'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Get database file path
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"

    # Query database for upload session
    $query = @"
SELECT
    UploadGuid,
    UserID,
    FileName,
    FileSize,
    TargetPath,
    ChunkSize,
    TotalChunks,
    ChunkBitmap,
    ReceivedBytes,
    UploadMethod,
    TempFilePath,
    StartTime,
    LastActivityTime,
    Status
FROM Upload_Sessions
WHERE UploadGuid = @Guid
"@

    $params = @{
        Guid = $guid
    }

    $result = Invoke-SqliteQuery -DataSource $dbFile -Query $query -SqlParameters $params

    if (-not $result) {
        # Not in database, check in-memory uploads
        if ($Global:PSWebServer.Uploads -and $Global:PSWebServer.Uploads.ContainsKey($guid)) {
            $uploadInfo = $Global:PSWebServer.Uploads[$guid]

            # Verify user owns this upload
            if ($uploadInfo.UserID -ne $userID) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Unauthorized: You do not own this upload'
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
                return
            }

            # Convert ChunkBitmap to array of booleans
            $chunkBitmapArray = @()
            for ($i = 0; $i -lt $uploadInfo.TotalChunks; $i++) {
                $chunkBitmapArray += $uploadInfo.ChunkBitmap[$i]
            }

            # Find missing chunks
            $missingChunks = @()
            for ($i = 0; $i -lt $uploadInfo.TotalChunks; $i++) {
                if (-not $uploadInfo.ChunkBitmap[$i]) {
                    $missingChunks += $i
                }
            }

            # Return in-memory upload status
            $data = @{
                guid = $guid
                fileName = $uploadInfo.FileName
                fileSize = $uploadInfo.FileSize
                chunkSize = $uploadInfo.ChunkSize
                totalChunks = $uploadInfo.TotalChunks
                receivedChunks = $uploadInfo.ReceivedChunks
                receivedBytes = $uploadInfo.ReceivedBytes
                chunkBitmap = $chunkBitmapArray
                missingChunks = $missingChunks
                uploadMethod = if ($uploadInfo.UploadMethod) { $uploadInfo.UploadMethod } else { 'unknown' }
                startTime = [int]([DateTimeOffset]$uploadInfo.CreatedAt).ToUnixTimeSeconds()
                lastActivityTime = [int]([DateTimeOffset]::Now).ToUnixTimeSeconds()
                uploadStatus = 'active'
                source = 'memory'
            }

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload session found in memory' -Data $data
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
            return
        }

        # Upload not found
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload session not found: $guid"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    # Verify user owns this upload
    if ($result.UserID -ne $userID) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Unauthorized: You do not own this upload'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
        return
    }

    # Parse ChunkBitmap from JSON
    $chunkBitmapArray = $result.ChunkBitmap | ConvertFrom-Json

    # Find missing chunks
    $missingChunks = @()
    for ($i = 0; $i -lt $result.TotalChunks; $i++) {
        if (-not $chunkBitmapArray[$i]) {
            $missingChunks += $i
        }
    }

    # Count received chunks
    $receivedChunks = ($chunkBitmapArray | Where-Object { $_ -eq $true }).Count

    # Return upload status
    $data = @{
        guid = $result.UploadGuid
        fileName = $result.FileName
        fileSize = $result.FileSize
        chunkSize = $result.ChunkSize
        totalChunks = $result.TotalChunks
        receivedChunks = $receivedChunks
        receivedBytes = $result.ReceivedBytes
        chunkBitmap = $chunkBitmapArray
        missingChunks = $missingChunks
        uploadMethod = $result.UploadMethod
        startTime = $result.StartTime
        lastActivityTime = $result.LastActivityTime
        uploadStatus = $result.Status
        source = 'database'
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Upload status queried: $guid" -Data @{
        UserID = $userID
        Guid = $guid
        ReceivedChunks = $receivedChunks
        TotalChunks = $result.TotalChunks
        Status = $result.Status
    }

    $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload session found' -Data $data
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        Guid = $guid
    }
}
