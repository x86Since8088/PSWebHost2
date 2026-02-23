param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Get progressive hash validation data for resumed upload

.DESCRIPTION
    Returns hash information for server-side partial upload file:
    - File size
    - First 128KB hash
    - Last 128KB hash
    - Hashes of first 128KB of every 10MB range

    Used by client to validate which ranges have been uploaded correctly
    and avoid re-uploading already received data.

.EXAMPLE
    GET /api/v1/files/upload-validate?guid=550e8400-e29b-41d4-a716-446655440000

    Response:
    {
        "status": "success",
        "data": {
            "fileSize": 52428800,
            "firstHash": "abc123...",
            "lastHash": "def456...",
            "rangeHashes": [
                { "offset": 0, "size": 131072, "hash": "abc123..." },
                { "offset": 10485760, "size": 131072, "hash": "ghi789..." },
                { "offset": 20971520, "size": 131072, "hash": "jkl012..." }
            ]
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

# Check if upload exists - first try database (persistent), then in-memory
$upload = $null
$tempFilePath = $null

try {
    # Query database for upload session
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"

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

    $result = Invoke-SqliteQuery -DataSource $dbFile -Query $query -SqlParameters @{ Guid = $guid }

    if ($result) {
        # Found in database
        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Found upload session in database: $guid"

        # Verify user owns this upload
        if ($result.UserID -ne $userID) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Access denied: upload belongs to another user'
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
            return
        }

        $tempFilePath = $result.TempFilePath
        $upload = @{
            Guid = $result.UploadGuid
            UserID = $result.UserID
            FileName = $result.FileName
            FileSize = $result.FileSize
            TargetPath = $result.TargetPath
            TempFilePath = $result.TempFilePath
        }
    }
    elseif ($Global:PSWebServer.Uploads -and $Global:PSWebServer.Uploads.ContainsKey($guid)) {
        # Not in database, check in-memory uploads
        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Found upload session in memory: $guid"

        $uploadInfo = $Global:PSWebServer.Uploads[$guid]

        # Verify user owns this upload
        if ($uploadInfo.UserID -ne $userID) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Access denied: upload belongs to another user'
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
            return
        }

        $tempFilePath = $uploadInfo.TempFilePath
        $upload = $uploadInfo
    }
    else {
        # Not found anywhere
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload not found: $guid"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to query upload session: $($_.Exception.Message)"
    # Fall back to in-memory check
    if ($Global:PSWebServer.Uploads -and $Global:PSWebServer.Uploads.ContainsKey($guid)) {
        $upload = $Global:PSWebServer.Uploads[$guid]
        $tempFilePath = $upload.TempFilePath
    } else {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload not found: $guid"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }
}

# Check temp file exists
if (-not (Test-Path $tempFilePath)) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Temp file not found: $tempFilePath"
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
    return
}

try {
    Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Computing progressive hashes for upload: $guid"

    # Get file size
    $fileItem = Get-Item $tempFilePath -ErrorAction Stop
    $fileSize = $fileItem.Length

    Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Temp file size: $fileSize bytes"

    if ($fileSize -eq 0) {
        # Empty file - return minimal data
        $hashData = @{
            fileSize = 0
            firstHash = ''
            lastHash = ''
            rangeHashes = @()
        }

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'No data uploaded yet' -Data $hashData
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        return
    }

    # Open file for reading
    $stream = [System.IO.File]::OpenRead($tempFilePath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        # Constants
        $HASH_CHUNK_SIZE = 128KB  # 131,072 bytes
        $RANGE_INTERVAL = 10MB    # 10,485,760 bytes

        # Compute first 128KB hash
        $firstHashData = $null
        $firstSize = if ($fileSize -lt $HASH_CHUNK_SIZE) { [int]$fileSize } else { [int]$HASH_CHUNK_SIZE }
        $buffer = New-Object byte[] $firstSize
        $stream.Position = 0
        $bytesRead = $stream.Read($buffer, 0, $firstSize)

        if ($bytesRead -gt 0) {
            $hashBytes = $sha256.ComputeHash($buffer, 0, $bytesRead)
            $firstHashData = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
        }

        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "First ${firstSize} bytes hash: $firstHashData"

        # Compute last 128KB hash
        $lastHashData = $null
        if ($fileSize -gt $HASH_CHUNK_SIZE) {
            $lastOffset = $fileSize - $HASH_CHUNK_SIZE
            $lastSize = [int]$HASH_CHUNK_SIZE
            $buffer = New-Object byte[] $lastSize
            $stream.Position = $lastOffset
            $bytesRead = $stream.Read($buffer, 0, $lastSize)

            if ($bytesRead -gt 0) {
                $hashBytes = $sha256.ComputeHash($buffer, 0, $bytesRead)
                $lastHashData = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
            }
        } else {
            # File smaller than 128KB - last hash same as first hash
            $lastHashData = $firstHashData
        }

        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Last ${HASH_CHUNK_SIZE} bytes hash: $lastHashData"

        # Compute hashes of first 128KB of every 10MB range
        $rangeHashes = @()
        $offset = [long]0

        while ($offset -lt $fileSize) {
            $remaining = $fileSize - $offset
            $rangeSize = if ($remaining -lt $HASH_CHUNK_SIZE) { [int]$remaining } else { [int]$HASH_CHUNK_SIZE }
            $buffer = New-Object byte[] $rangeSize
            $stream.Position = $offset
            $bytesRead = $stream.Read($buffer, 0, $rangeSize)

            if ($bytesRead -gt 0) {
                $hashBytes = $sha256.ComputeHash($buffer, 0, $bytesRead)
                $rangeHash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

                $rangeHashes += @{
                    offset = $offset
                    size = $bytesRead
                    hash = $rangeHash
                }

                Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Range at offset ${offset}: ${bytesRead} bytes, hash: $rangeHash"
            }

            # Move to next 10MB boundary
            $offset += $RANGE_INTERVAL
        }

        # Build response
        $hashData = @{
            fileSize = $fileSize
            firstHash = $firstHashData
            lastHash = $lastHashData
            rangeHashes = $rangeHashes
            rangeInterval = $RANGE_INTERVAL
            hashChunkSize = $HASH_CHUNK_SIZE
        }

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Generated $($rangeHashes.Count) range hashes for upload: $guid (fileSize: $fileSize)"

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Hash validation data computed' -Data $hashData
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json

    } finally {
        $stream.Close()
        $stream.Dispose()
        $sha256.Dispose()
    }

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to compute progressive hashes: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}
