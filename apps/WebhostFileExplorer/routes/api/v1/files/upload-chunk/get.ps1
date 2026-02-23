param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    WebSocket upgrade endpoint for binary file upload streaming

.DESCRIPTION
    Detects WebSocket upgrade request and handles binary chunk streaming
    using WebSocket frames. Falls back to regular GET if not WebSocket.

.EXAMPLE
    GET /api/v1/files/upload-chunk?guid=550e8400-e29b-41d4-a716-446655440000
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
    Sec-WebSocket-Version: 13
#>

# Import File Explorer helper module functions
try {Import-TrackedModule "FileExplorerHelper"
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

# Check if this is a WebSocket upgrade request
if ($Context.Request.IsWebSocketRequest) {
    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "WebSocket upload started: $($uploadInfo.FileName)" -Data @{
        UserID = $userID
        Guid = $guid
        FileSize = $uploadInfo.FileSize
        TotalChunks = $uploadInfo.TotalChunks
    }

    try {
        # Accept WebSocket connection (no subProtocol)
        $wsContext = $Context.AcceptWebSocketAsync([NullString]::Value).GetAwaiter().GetResult()
        $webSocket = $wsContext.WebSocket

        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "WebSocket connection established" -Data @{
            Guid = $guid
            State = $webSocket.State.ToString()
        }

        # Buffer for receiving messages (10MB to accommodate 5MB chunks + overhead)
        $buffer = New-Object byte[] (10 * 1024 * 1024)

        # Track current chunk metadata
        $currentChunkNumber = $null
        $currentBytesRemaining = $null

        # Message loop
        while ($webSocket.State -eq 'Open') {
            try {
                # Receive complete message (may be fragmented across multiple frames)
                $messageBuffer = New-Object System.Collections.Generic.List[byte]
                $messageType = $null

                do {
                    $receiveTask = $webSocket.ReceiveAsync(
                        [ArraySegment[byte]]::new($buffer),
                        [System.Threading.CancellationToken]::None
                    )
                    $result = $receiveTask.GetAwaiter().GetResult()

                    # Store message type from first frame
                    if ($null -eq $messageType) {
                        $messageType = $result.MessageType
                    }

                    # Append received bytes to message buffer
                    for ($i = 0; $i -lt $result.Count; $i++) {
                        $messageBuffer.Add($buffer[$i])
                    }

                } while (-not $result.EndOfMessage -and $webSocket.State -eq 'Open')

                if ($messageType -eq 'Close') {
                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "WebSocket close requested" -Data @{
                        Guid = $guid
                        CloseStatus = $result.CloseStatus
                    }

                    # Send close acknowledgment
                    $closeTask = $webSocket.CloseAsync(
                        [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                        'Upload complete',
                        [System.Threading.CancellationToken]::None
                    )
                    $closeTask.GetAwaiter().GetResult()
                    break
                }
                elseif ($messageType -eq 'Text') {
                    # Control message - chunk metadata
                    $messageBytes = $messageBuffer.ToArray()
                    $jsonText = [System.Text.Encoding]::UTF8.GetString($messageBytes)
                    $metadata = $jsonText | ConvertFrom-Json

                    if ($metadata.type -eq 'chunk') {
                        # Store metadata for next binary frame
                        $currentChunkNumber = [int]$metadata.chunkNumber
                        $currentBytesRemaining = [long]$metadata.bytesRemaining

                        # Log once per 60 seconds (time-based throttle) or on first chunk
                        $now = Get-Date
                        $timeSinceLastLog = ($now - $uploadInfo.LastLogTime).TotalSeconds
                        if ($timeSinceLastLog -ge 60 -or $currentChunkNumber -eq 0) {
                            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "WebSocket chunk metadata received: $currentChunkNumber/$($uploadInfo.TotalChunks) ($([math]::Round(($currentChunkNumber / $uploadInfo.TotalChunks) * 100))%)" -Data @{
                                Guid = $guid
                                ChunkNumber = $currentChunkNumber
                                BytesRemaining = $currentBytesRemaining
                                Method = 'WebSocket'
                            }
                            $uploadInfo.LastLogTime = $now
                        }
                    }
                    elseif ($metadata.type -eq 'getProgress') {
                        # Client requesting progress update
                        $progressResponse = @{
                            type = 'progress'
                            receivedChunks = $uploadInfo.ReceivedChunks
                            totalChunks = $uploadInfo.TotalChunks
                            receivedBytes = $uploadInfo.ReceivedBytes
                            complete = $uploadInfo.ReceivedChunks -eq $uploadInfo.TotalChunks
                        } | ConvertTo-Json -Compress

                        $progressBytes = [System.Text.Encoding]::UTF8.GetBytes($progressResponse)
                        $sendTask = $webSocket.SendAsync(
                            [ArraySegment[byte]]::new($progressBytes),
                            'Text',
                            $true,
                            [System.Threading.CancellationToken]::None
                        )
                        $sendTask.GetAwaiter().GetResult()
                    }
                }
                elseif ($messageType -eq 'Binary') {
                    # Binary chunk data
                    if ($null -eq $currentChunkNumber) {
                        # Binary message without metadata - skip silently
                        continue
                    }

                    # Extract complete chunk data from message buffer
                    $chunkData = $messageBuffer.ToArray()
                    $chunkSize = $chunkData.Length

                    # Log once per 60 seconds (time-based throttle) or on first chunk - shares same timer as metadata
                    $now = Get-Date
                    $timeSinceLastLog = ($now - $uploadInfo.LastLogTime).TotalSeconds
                    if ($timeSinceLastLog -ge 60 -or $currentChunkNumber -eq 0) {
                        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "WebSocket binary chunk received: $currentChunkNumber/$($uploadInfo.TotalChunks) ($('{0:N0}' -f $chunkSize) bytes, $([math]::Round(($currentChunkNumber / $uploadInfo.TotalChunks) * 100))%)" -Data @{
                            Guid = $guid
                            ChunkNumber = $currentChunkNumber
                            ChunkSize = $chunkSize
                            Method = 'WebSocket'
                        }
                        $uploadInfo.LastLogTime = $now
                    }

                    # Check if chunk already received (idempotency)
                    if ($uploadInfo.ChunkBitmap[$currentChunkNumber]) {
                        # Skip duplicate chunk silently (no log)
                    }
                    else {
                        # Write chunk using asynchronous file I/O
                        $lockObj = $Global:PSWebServer.UploadLocks[$guid]

                        # Acquire lock
                        [System.Threading.Monitor]::Enter($lockObj)
                        try {
                            # Calculate write position
                            $position = [long]$currentChunkNumber * $uploadInfo.ChunkSize

                            # Open file with shared read/write access and async support
                            $fileStream = [System.IO.File]::Open(
                                $uploadInfo.TempFilePath,
                                [System.IO.FileMode]::OpenOrCreate,
                                [System.IO.FileAccess]::Write,
                                [System.IO.FileShare]::ReadWrite
                            )

                            try {
                                # Seek to position
                                $fileStream.Seek($position, [System.IO.SeekOrigin]::Begin) | Out-Null

                                # Write chunk data asynchronously (offloads to thread pool)
                                $writeTask = $fileStream.WriteAsync($chunkData, 0, $chunkData.Length)
                                $writeTask.GetAwaiter().GetResult()  # Wait for async write to complete

                                # Flush every 10 chunks or on final chunk (reduces disk I/O overhead)
                                $shouldFlush = (($uploadInfo.ReceivedChunks + 1) % 10 -eq 0) -or (($uploadInfo.ReceivedChunks + 1) -eq $uploadInfo.TotalChunks)
                                if ($shouldFlush) {
                                    $flushTask = $fileStream.FlushAsync()
                                    $flushTask.GetAwaiter().GetResult()
                                }
                            }
                            finally {
                                $fileStream.Close()
                            }

                            # Update metadata
                            $uploadInfo.ChunkBitmap[$currentChunkNumber] = $true
                            $uploadInfo.ReceivedChunks++
                            $uploadInfo.ReceivedBytes += $chunkSize

                            # Update database (persisted for resume capability)
                            try {
                                $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
                                $chunkBitmapJson = $uploadInfo.ChunkBitmap | ConvertTo-Json -Compress
                                $lastActivityTime = [int]([DateTimeOffset]::Now).ToUnixTimeSeconds()

                                $updateQuery = @"
UPDATE Upload_Sessions
SET ChunkBitmap = @ChunkBitmap,
    ReceivedBytes = @ReceivedBytes,
    LastActivityTime = @LastActivityTime,
    UploadMethod = 'websocket'
WHERE UploadGuid = @Guid
"@

                                $updateParams = @{
                                    Guid = $guid
                                    ChunkBitmap = $chunkBitmapJson
                                    ReceivedBytes = $uploadInfo.ReceivedBytes
                                    LastActivityTime = $lastActivityTime
                                }

                                Invoke-SqliteQuery -DataSource $dbFile -Query $updateQuery -SqlParameters $updateParams
                            }
                            catch {
                                # Log warning but don't fail the upload
                                Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to update upload session in database: $($_.Exception.Message)" -Data @{
                                    Guid = $guid
                                    ChunkNumber = $currentChunkNumber
                                }
                            }

                            # Update FileTransfers metrics
                            $finalFilePath = Join-Path $uploadInfo.TargetPath $uploadInfo.FileName
                            if ($Global:PSWebServer.FileTransfers -and
                                $Global:PSWebServer.FileTransfers[$userID] -and
                                $Global:PSWebServer.FileTransfers[$userID][$finalFilePath]) {
                                $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Metrics.BytesTransferred = $uploadInfo.ReceivedBytes
                                $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Metrics.ChunksReceived = $uploadInfo.ReceivedChunks
                                $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Metrics.LastUpdateTime = Get-Date
                            }

                        } finally {
                            [System.Threading.Monitor]::Exit($lockObj)
                        }
                    }

                    # Send progress response
                    $complete = $uploadInfo.ReceivedChunks -eq $uploadInfo.TotalChunks

                    $progressResponse = @{
                        type = 'progress'
                        chunkNumber = $currentChunkNumber
                        receivedChunks = $uploadInfo.ReceivedChunks
                        totalChunks = $uploadInfo.TotalChunks
                        receivedBytes = $uploadInfo.ReceivedBytes
                        complete = $complete
                    } | ConvertTo-Json -Compress

                    $progressBytes = [System.Text.Encoding]::UTF8.GetBytes($progressResponse)
                    $sendTask = $webSocket.SendAsync(
                        [ArraySegment[byte]]::new($progressBytes),
                        'Text',
                        $true,
                        [System.Threading.CancellationToken]::None
                    )
                    $sendTask.GetAwaiter().GetResult()

                    # Check if upload complete
                    if ($complete) {
                        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "All chunks received via WebSocket, finalizing: $($uploadInfo.FileName)" -Data @{
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

                        # Calculate completion stats
                        $duration = ((Get-Date) - $uploadInfo.CreatedAt).TotalSeconds
                        $speedMBps = if ($duration -gt 0) {
                            [math]::Round(($uploadInfo.FileSize / 1024 / 1024) / $duration, 2)
                        } else {
                            0
                        }

                        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "WebSocket upload completed: $($uploadInfo.FileName)" -Data @{
                            UserID = $userID
                            Guid = $guid
                            FinalPath = $finalFilePath
                            Size = $finalFileInfo.Length
                            Chunks = $uploadInfo.TotalChunks
                            Duration = $duration
                            Method = 'WebSocket'
                        }

                        # Finalize FileTransfers metadata
                        if ($Global:PSWebServer.FileTransfers -and
                            $Global:PSWebServer.FileTransfers[$userID] -and
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath]) {
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Metrics.Status = 'completed'
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Metrics.BytesTransferred = $uploadInfo.FileSize
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Metrics.ChunksReceived = $uploadInfo.TotalChunks
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Summary.Completed = Get-Date
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Summary.Duration = $duration
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Summary.AverageSpeed = $speedMBps
                            $Global:PSWebServer.FileTransfers[$userID][$finalFilePath].Summary.Success = $true
                        }

                        # Remove completed upload session from database (no longer needed for resume)
                        try {
                            $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
                            $deleteQuery = "DELETE FROM Upload_Sessions WHERE UploadGuid = @Guid"
                            Invoke-SqliteQuery -DataSource $dbFile -Query $deleteQuery -SqlParameters @{ Guid = $guid }

                            Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Upload session removed from database (completed): $guid"
                        }
                        catch {
                            Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to delete completed upload session from database: $($_.Exception.Message)" -Data @{
                                Guid = $guid
                            }
                        }

                        # Send completion message
                        $completionResponse = @{
                            type = 'complete'
                            fileName = $uploadInfo.FileName
                            size = $finalFileInfo.Length
                        } | ConvertTo-Json -Compress

                        $completionBytes = [System.Text.Encoding]::UTF8.GetBytes($completionResponse)
                        $sendTask = $webSocket.SendAsync(
                            [ArraySegment[byte]]::new($completionBytes),
                            'Text',
                            $true,
                            [System.Threading.CancellationToken]::None
                        )
                        $sendTask.GetAwaiter().GetResult()

                        # Cleanup
                        $Global:PSWebServer.Uploads.Remove($guid)
                        $Global:PSWebServer.UploadTempFiles.Remove($guid)
                        $Global:PSWebServer.UploadLocks.Remove($guid)

                        # Close WebSocket
                        $closeTask = $webSocket.CloseAsync(
                            [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                            'Upload complete',
                            [System.Threading.CancellationToken]::None
                        )
                        $closeTask.GetAwaiter().GetResult()
                        break
                    }

                    # Don't reset chunk metadata - allows idempotent retries if frames arrive out of order
                    # Metadata will be updated when next 'chunk' metadata frame arrives
                }
            }
            catch {
                Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "WebSocket message loop error: $($_.Exception.Message)" -Data @{
                    Guid = $guid
                    Error = $_.Exception.ToString()
                }

                # Send error to client
                $errorResponse = @{
                    type = 'error'
                    message = $_.Exception.Message
                } | ConvertTo-Json -Compress

                $errorBytes = [System.Text.Encoding]::UTF8.GetBytes($errorResponse)
                try {
                    $sendTask = $webSocket.SendAsync(
                        [ArraySegment[byte]]::new($errorBytes),
                        'Text',
                        $true,
                        [System.Threading.CancellationToken]::None
                    )
                    $sendTask.GetAwaiter().GetResult()
                } catch {
                    # Ignore send errors
                }

                break
            }
        }

        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "WebSocket connection closed" -Data @{
            Guid = $guid
            State = $webSocket.State.ToString()
        }

    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "WebSocket error: $($_.Exception.Message)" -Data @{
            UserID = $userID
            Guid = $guid
            Error = $_.Exception.ToString()
        }

        # DO NOT cleanup upload metadata on WebSocket errors!
        # The client may fall back to PUT chunks, so the upload must remain available.
        # Cleanup only happens on:
        # 1. Successful completion (inside the message loop)
        # 2. Explicit cancellation (POST cancel endpoint)

        # Try to send error response if WebSocket is still open
        if ($webSocket -and $webSocket.State -eq 'Open') {
            try {
                $closeTask = $webSocket.CloseAsync(
                    [System.Net.WebSockets.WebSocketCloseStatus]::InternalServerError,
                    'WebSocket upload failed',
                    [System.Threading.CancellationToken]::None
                )
                $closeTask.GetAwaiter().GetResult()
            } catch {
                # Ignore close errors
            }
        }
    }
}
else {
    # Not a WebSocket request - return upgrade instructions
    $json = New-WebHostFileExplorerResponse -Status 'info' -Message 'WebSocket upgrade required' -Data @{
        guid = $guid
        fileName = $uploadInfo.FileName
        fileSize = $uploadInfo.FileSize
        receivedChunks = $uploadInfo.ReceivedChunks
        totalChunks = $uploadInfo.TotalChunks
        instructions = 'Send WebSocket upgrade request with Upgrade: websocket header'
    }
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
