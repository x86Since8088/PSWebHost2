param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Upload binary chunk data with direct file writing

.DESCRIPTION
    PUT binary data with custom header format - writes directly to temp file
    using synchronized file I/O to support concurrent chunk uploads from
    different runspaces.

    Binary Protocol:
    - Bytes 0-1: Random unsigned 16-bit number (for validation/sync)
    - Bytes 2-5: Chunk number (unsigned 32-bit integer)
    - Bytes 6-9: Bytes remaining in transfer (unsigned 32-bit integer)
    - Bytes 10+: Actual file chunk data

.EXAMPLE
    PUT /api/v1/files/upload-chunk?guid=550e8400-e29b-41d4-a716-446655440000
    Content-Type: application/octet-stream
    Body: [10 bytes header + chunk data]
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

# Check if upload exists
if (-not $Global:PSWebServer.Uploads -or -not $Global:PSWebServer.Uploads.ContainsKey($guid)) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload not found: $guid"
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
    return
}

$uploadInfo = $Global:PSWebServer.Uploads[$guid]

# Verify user owns this upload
if ($uploadInfo.UserID -ne $userID) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Unauthorized: You do not own this upload'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
    return
}

try {
    # Read binary data from request body
    $memStream = New-Object System.IO.MemoryStream
    $Request.InputStream.CopyTo($memStream)
    $chunkData = $memStream.ToArray()
    $memStream.Close()

    # Validate minimum size (10 bytes header + at least 1 byte data)
    if ($chunkData.Length -lt 11) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Invalid chunk data: minimum 11 bytes required (10 byte header + data)"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Parse header
    # Bytes 0-1: Random uint16 (little-endian)
    $randomValue = [BitConverter]::ToUInt16($chunkData, 0)

    # Bytes 2-5: Chunk number uint32 (little-endian)
    $chunkNumber = [BitConverter]::ToUInt32($chunkData, 2)

    # Bytes 6-9: Bytes remaining uint32 (little-endian)
    $bytesRemaining = [BitConverter]::ToUInt32($chunkData, 6)

    # Extract actual chunk data (skip 10 byte header)
    $actualChunkData = $chunkData[10..($chunkData.Length - 1)]
    $actualChunkSize = $actualChunkData.Length

    # Log once per 15 seconds (time-based throttle)
    $now = Get-Date
    $timeSinceLastLog = ($now - $uploadInfo.LastLogTime).TotalSeconds
    if ($timeSinceLastLog -ge 15 -or $chunkNumber -eq 0) {
        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Chunk received: $chunkNumber/$($uploadInfo.TotalChunks) ($('{0:N0}' -f $actualChunkSize) bytes, $([math]::Round(($chunkNumber / $uploadInfo.TotalChunks) * 100))%)" -Data @{
            UserID = $userID
            Guid = $guid
            ChunkNumber = $chunkNumber
            ChunkSize = $actualChunkSize
            BytesRemaining = $bytesRemaining
        }
        $uploadInfo.LastLogTime = $now
    }

    # Validate chunk number
    if ($chunkNumber -ge $uploadInfo.TotalChunks) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Invalid chunk number: $chunkNumber (expected 0-$($uploadInfo.TotalChunks - 1))"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Check if chunk already received (idempotency)
    if ($uploadInfo.ChunkBitmap[$chunkNumber]) {
        # Skip duplicate chunk silently (idempotent retry - no log needed)

        # Return success (idempotent)
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Chunk already received (idempotent)' -Data @{
            chunkNumber = $chunkNumber
            receivedChunks = $uploadInfo.ReceivedChunks
            totalChunks = $uploadInfo.TotalChunks
            complete = $uploadInfo.ReceivedChunks -eq $uploadInfo.TotalChunks
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        return
    }

    # ========================================================================
    # SYNCHRONIZED DIRECT FILE WRITE
    # ========================================================================
    # Get lock object for this upload
    $lockObj = $Global:PSWebServer.UploadLocks[$guid]

    # Acquire lock (thread-safe across runspaces)
    [System.Threading.Monitor]::Enter($lockObj)
    try {
        # Calculate write position based on chunk number
        $position = [long]$chunkNumber * $uploadInfo.ChunkSize

        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Writing chunk to position $position" -Data @{
            Guid = $guid
            ChunkNumber = $chunkNumber
            Position = $position
            Size = $actualChunkSize
        }

        # Open file with shared read/write access (allows concurrent opens)
        $fileStream = [System.IO.File]::Open(
            $uploadInfo.TempFilePath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )

        try {
            # Seek to chunk position
            $fileStream.Seek($position, [System.IO.SeekOrigin]::Begin) | Out-Null

            # Write chunk data asynchronously (offloads to thread pool)
            $writeTask = $fileStream.WriteAsync($actualChunkData, 0, $actualChunkData.Length)
            $writeTask.GetAwaiter().GetResult()  # Wait for async write to complete

            # Flush asynchronously
            $flushTask = $fileStream.FlushAsync()
            $flushTask.GetAwaiter().GetResult()

            Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Chunk written successfully" -Data @{
                Guid = $guid
                ChunkNumber = $chunkNumber
                BytesWritten = $actualChunkData.Length
            }
        }
        finally {
            $fileStream.Close()
        }

        # Update metadata (still under lock)
        $uploadInfo.ChunkBitmap[$chunkNumber] = $true
        $uploadInfo.ReceivedChunks++
        $uploadInfo.ReceivedBytes += $actualChunkSize

    } finally {
        [System.Threading.Monitor]::Exit($lockObj)
    }
    # ========================================================================

    # Check if all chunks received
    $allChunksReceived = $uploadInfo.ReceivedChunks -eq $uploadInfo.TotalChunks

    if ($allChunksReceived) {
        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "All chunks received, finalizing upload: $($uploadInfo.FileName)" -Data @{
            UserID = $userID
            Guid = $guid
            TotalChunks = $uploadInfo.TotalChunks
            TotalBytes = $uploadInfo.ReceivedBytes
        }

        # Verify file size
        $tempFileInfo = Get-Item $uploadInfo.TempFilePath
        if ($tempFileInfo.Length -ne $uploadInfo.FileSize) {
            throw "File size mismatch: expected $($uploadInfo.FileSize) bytes, got $($tempFileInfo.Length) bytes"
        }

        # Move to final location
        $finalFilePath = Join-Path $uploadInfo.TargetPath $uploadInfo.FileName

        # Handle existing file (overwrite)
        if (Test-Path $finalFilePath) {
            Remove-Item -Path $finalFilePath -Force
        }

        Move-Item -Path $uploadInfo.TempFilePath -Destination $finalFilePath -Force

        # Get final file info
        $finalFileInfo = Get-Item $finalFilePath

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Binary upload completed: $($uploadInfo.FileName)" -Data @{
            UserID = $userID
            Guid = $guid
            FinalPath = $finalFilePath
            Size = $finalFileInfo.Length
            Chunks = $uploadInfo.TotalChunks
            Duration = ((Get-Date) - $uploadInfo.CreatedAt).TotalSeconds
        }

        # Cleanup
        $Global:PSWebServer.Uploads.Remove($guid)
        $Global:PSWebServer.UploadTempFiles.Remove($guid)
        $Global:PSWebServer.UploadLocks.Remove($guid)

        # Return completion response
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload completed successfully' -Data @{
            fileName = $uploadInfo.FileName
            size = $finalFileInfo.Length
            complete = $true
            receivedChunks = $uploadInfo.TotalChunks
            totalChunks = $uploadInfo.TotalChunks
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
    else {
        # More chunks needed
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Chunk received' -Data @{
            chunkNumber = $chunkNumber
            receivedChunks = $uploadInfo.ReceivedChunks
            totalChunks = $uploadInfo.TotalChunks
            complete = $false
            bytesRemaining = $bytesRemaining
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
}
catch {
    # Cleanup on error
    if ($uploadInfo -and $uploadInfo.TempFilePath -and (Test-Path $uploadInfo.TempFilePath)) {
        Remove-Item -Path $uploadInfo.TempFilePath -Force -ErrorAction SilentlyContinue
    }

    # Remove from global hashtables on error
    if ($Global:PSWebServer.Uploads.ContainsKey($guid)) {
        $Global:PSWebServer.Uploads.Remove($guid)
    }
    if ($Global:PSWebServer.UploadTempFiles.ContainsKey($guid)) {
        $Global:PSWebServer.UploadTempFiles.Remove($guid)
    }
    if ($Global:PSWebServer.UploadLocks.ContainsKey($guid)) {
        $Global:PSWebServer.UploadLocks.Remove($guid)
    }

    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        Guid = $guid
        ChunkNumber = $chunkNumber
    }
}
