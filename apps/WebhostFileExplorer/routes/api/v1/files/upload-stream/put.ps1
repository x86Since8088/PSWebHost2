param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# PUT /api/v1/files/upload-stream - Streaming upload with persistent file handle
# High-performance upload without chunking overhead
# Client sends entire file in single request, server reads incrementally

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

# Parse JSON body for initial metadata
try {
    # Check if this is init request (has Content-Type: application/json)
    if ($Request.ContentType -and $Request.ContentType.StartsWith('application/json')) {
        # INIT phase: Client sends metadata
        $body = [System.IO.StreamReader]::new($Request.InputStream).ReadToEnd()
        $data = $body | ConvertFrom-Json

        # Validate required fields
        if (-not $data.fileName -or -not $data.fileSize -or -not $data.targetPath) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'fileName, fileSize, and targetPath required'
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
            return
        }

        $fileName = $data.fileName
        $fileSize = [long]$data.fileSize
        $targetPath = $data.targetPath

        # Validate session
        $userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
        if (-not $userID) { return }

        $roles = $sessiondata.Roles

        # Resolve target path using FileExplorerHelper function
        $targetResult = Resolve-WebHostFileExplorerPath -LogicalPath $targetPath -UserID $userID -Roles $roles -Response $Response -RequiredPermission 'write'
        if (-not $targetResult) { return }

        # targetResult is already validated by Resolve-WebHostFileExplorerPath (it returns $null and sends error response if invalid)

        # Check if resuming an existing upload
        $resumeGuid = $data.resumeGuid
        $startOffset = 0

        if ($resumeGuid) {
            # Resuming existing upload - check if temp file exists
            $tempDir = Join-Path $Global:PSWebServer.Project_Root.Path "uploads\temp"
            $tempFilePath = Join-Path $tempDir "streamUpload_$resumeGuid.tmp"

            if (Test-Path $tempFilePath) {
                $existingFile = Get-Item $tempFilePath
                $startOffset = $existingFile.Length
                $uploadGuid = $resumeGuid

                Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Resuming streaming upload - GUID: $uploadGuid, StartOffset: $startOffset" -Data @{
                    UserID = $userID
                    FileName = $fileName
                    StartOffset = $startOffset
                    FileSize = $fileSize
                }
            } else {
                # Resume GUID provided but temp file doesn't exist - start fresh
                $uploadGuid = [guid]::NewGuid().ToString()
                $tempFilePath = Join-Path $tempDir "streamUpload_$uploadGuid.tmp"
            }
        } else {
            # New upload - generate GUID
            $uploadGuid = [guid]::NewGuid().ToString()

            # Create temp file path
            $tempDir = Join-Path $Global:PSWebServer.Project_Root.Path "uploads\temp"
            if (-not (Test-Path $tempDir)) {
                New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            }
            $tempFilePath = Join-Path $tempDir "streamUpload_$uploadGuid.tmp"
        }

        # Open streaming upload session with resume support
        $saveUploadScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Save-IncomingFileUpload.ps1"
        $openResult = & $saveUploadScript -Action 'Open' -UploadGuid $uploadGuid -FilePath $tempFilePath -FileSize $fileSize -StartOffset $startOffset

        if (-not $openResult.Success) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Failed to open upload session: $($openResult.Message)"
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 500 -JsonContent $json
            return
        }

        # Store upload metadata
        if (-not $Global:PSWebServer.Uploads) {
            $Global:PSWebServer.Uploads = @{}
        }

        $Global:PSWebServer.Uploads[$uploadGuid] = @{
            Guid = $uploadGuid
            UserID = $userID
            FileName = $fileName
            FileSize = $fileSize
            TempFilePath = $tempFilePath
            TargetPhysicalPath = $targetResult.PhysicalPath
            TargetLogicalPath = $targetPath
            BytesReceived = $startOffset  # Start from resume offset
            BytesCommitted = $startOffset  # Safe resume point
            LastUpdateTime = Get-Date  # Track last FileTransfers update
            StartTime = Get-Date
            StreamingUpload = $true
        }

        # Initialize FileTransfers metadata structure
        if (-not $Global:PSWebServer.FileTransfers) {
            $Global:PSWebServer.FileTransfers = @{}
        }
        if (-not $Global:PSWebServer.FileTransfers[$userID]) {
            $Global:PSWebServer.FileTransfers[$userID] = [hashtable]::Synchronized(@{})
        }

        $finalPath = Join-Path $targetResult.PhysicalPath $fileName
        $Global:PSWebServer.FileTransfers[$userID][$finalPath] = [hashtable]::Synchronized([ordered]@{
            Name = $fileName
            RemotePath = $targetPath
            LocalPath = $finalPath
            SessionID = $uploadGuid
            UserID = $userID
            Metrics = [hashtable]::Synchronized([ordered]@{
                FileSize = $fileSize
                BytesTransferred = 0
                StartTime = Get-Date
                LastUpdateTime = Get-Date
                Method = 'streaming'
                Status = 'active'
            })
            Summary = [hashtable]::Synchronized([ordered]@{
                Initialized = Get-Date
                Completed = $null
                Duration = $null
                AverageSpeed = 0
                Success = $false
            })
        })

        # Return upload GUID and resume info to client
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload session initialized' -Data @{
            guid = $uploadGuid
            fileSize = $fileSize
            startOffset = $startOffset
            bytesReceived = $startOffset
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        return
    }

    # STREAM phase: Client sends binary data
    # Extract GUID from query string
    $guid = $Request.QueryString['guid']
    if (-not $guid) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Upload GUID required'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Get upload metadata
    if (-not $Global:PSWebServer.Uploads.ContainsKey($guid)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Upload session not found'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    $uploadInfo = $Global:PSWebServer.Uploads[$guid]
    $saveUploadScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Save-IncomingFileUpload.ps1"

    # Check for Range header (resume support)
    $rangeHeader = $Request.Headers['Content-Range']
    $startOffset = 0

    if ($rangeHeader) {
        # Parse Content-Range header: "bytes START-END/TOTAL"
        # Example: "bytes 52428800-104857599/104857600"
        if ($rangeHeader -match 'bytes\s+(\d+)-(\d+)/(\d+)') {
            $startOffset = [long]$matches[1]
            $endOffset = [long]$matches[2]
            $totalSize = [long]$matches[3]

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Resume streaming upload at offset $startOffset for GUID: $guid" -Data @{
                StartOffset = $startOffset
                EndOffset = $endOffset
                TotalSize = $totalSize
            }

            # Validate offset is within expected range
            if ($startOffset -gt $uploadInfo.FileSize) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Invalid range: start offset $startOffset exceeds file size $($uploadInfo.FileSize)"
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 416 -JsonContent $json
                return
            }

            # Update BytesReceived to resume point
            $uploadInfo.BytesReceived = $startOffset
        }
    }

    # Read incoming stream and write to file incrementally
    $inputStream = $Request.InputStream
    $buffer = New-Object byte[] 4194304  # 4MB read buffer (matches FileStream buffer for maximum throughput)
    $totalBytesRead = $startOffset  # Start from resume offset
    $startTime = Get-Date
    $maxReadRetries = 3
    $readRetryDelayMs = 100

    try {
        while ($true) {
            # Read from HTTP input stream with retry logic
            $bytesRead = 0
            $readSuccess = $false
            $readRetryCount = 0
            $lastReadError = $null

            while (-not $readSuccess -and $readRetryCount -le $maxReadRetries) {
                try {
                    # Use ReadAsync with cancellation token for better control
                    $cts = [System.Threading.CancellationTokenSource]::new(30000)  # 30 second read timeout

                    try {
                        $readTask = $inputStream.ReadAsync($buffer, 0, $buffer.Length, $cts.Token)
                        $bytesRead = $readTask.GetAwaiter().GetResult()
                        $readSuccess = $true

                        if ($readRetryCount -gt 0) {
                            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "HTTP read succeeded after $readRetryCount retries for GUID: $guid" -Data @{
                                Guid = $guid
                                RetryCount = $readRetryCount
                            }
                        }
                    }
                    catch [System.OperationCanceledException] {
                        $lastReadError = "HTTP read timed out after 30 seconds"
                        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "HTTP read timeout for GUID: $guid (attempt $($readRetryCount + 1)/$($maxReadRetries + 1)): $lastReadError" -Data @{
                            Guid = $guid
                            Attempt = $readRetryCount + 1
                        }
                    }
                    catch [System.IO.IOException] {
                        # I/O operation aborted - this is the error we're seeing
                        $lastReadError = $_.Exception.Message
                        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "HTTP read I/O error for GUID: $guid (attempt $($readRetryCount + 1)/$($maxReadRetries + 1)): $lastReadError" -Data @{
                            Guid = $guid
                            Attempt = $readRetryCount + 1
                            ErrorType = 'IOException'
                        }
                    }
                    catch {
                        $lastReadError = $_.Exception.Message
                        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "HTTP read error for GUID: $guid (attempt $($readRetryCount + 1)/$($maxReadRetries + 1)): $lastReadError" -Data @{
                            Guid = $guid
                            Attempt = $readRetryCount + 1
                            ErrorType = $_.Exception.GetType().Name
                        }
                    }
                    finally {
                        $cts.Dispose()
                    }
                }
                catch {
                    $lastReadError = $_.Exception.Message
                    Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "HTTP read setup error for GUID: $guid (attempt $($readRetryCount + 1)/$($maxReadRetries + 1)): $lastReadError" -Data @{
                        Guid = $guid
                        Attempt = $readRetryCount + 1
                    }
                }

                if (-not $readSuccess) {
                    $readRetryCount++

                    if ($readRetryCount -le $maxReadRetries) {
                        # Exponential backoff
                        $delayMs = $readRetryDelayMs * [Math]::Pow(2, $readRetryCount - 1)
                        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Retrying HTTP read for GUID: $guid after ${delayMs}ms delay..." -Data @{
                            Guid = $guid
                            DelayMs = $delayMs
                        }
                        Start-Sleep -Milliseconds $delayMs
                    }
                    else {
                        # All retries exhausted - this connection is lost
                        # Save current state for resume
                        Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "HTTP read failed after $maxReadRetries retries for GUID: $guid - Connection lost, upload can be resumed" -Data @{
                            Guid = $guid
                            BytesCommitted = $uploadInfo.BytesCommitted
                            LastError = $lastReadError
                        }

                        # Don't abort - leave temp file for resume
                        & $saveUploadScript -Action 'Close' -UploadGuid $guid | Out-Null

                        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Connection lost after $maxReadRetries retries: $lastReadError. Upload can be resumed from $($uploadInfo.BytesCommitted) bytes." -Data @{
                            canResume = $true
                            uploadGuid = $guid
                            bytesCommitted = $uploadInfo.BytesCommitted
                            fileSize = $uploadInfo.FileSize
                        }
                        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 503 -JsonContent $json
                        return
                    }
                }
            }

            # Check if end of stream
            if ($bytesRead -eq 0) {
                break  # End of stream
            }

            # Optimization: Only create new array if we read partial buffer (last chunk)
            if ($bytesRead -eq $buffer.Length) {
                # Full buffer read - pass directly (no copy needed)
                $dataToWrite = $buffer
            } else {
                # Partial read (last chunk) - extract only bytes read
                $dataToWrite = New-Object byte[] $bytesRead
                [Array]::Copy($buffer, 0, $dataToWrite, 0, $bytesRead)
            }

            # Write to file (Save-IncomingFileUpload.ps1 has its own retry logic)
            $writeResult = & $saveUploadScript -Action 'Write' -UploadGuid $guid -Data $dataToWrite

            if (-not $writeResult.Success) {
                # Write failed - abort upload
                & $saveUploadScript -Action 'Abort' -UploadGuid $guid | Out-Null
                $Global:PSWebServer.Uploads.Remove($guid) | Out-Null

                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Write failed: $($writeResult.Message)"
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 500 -JsonContent $json
                return
            }

            $totalBytesRead += $bytesRead
            $uploadInfo.BytesReceived = $writeResult.BytesWritten

            # Update committed bytes (safe for resume)
            if ($writeResult.BytesCommitted) {
                $uploadInfo.BytesCommitted = $writeResult.BytesCommitted
            }

            # Update FileTransfers metrics only every 10 seconds (or on completion)
            $now = Get-Date
            $timeSinceLastUpdate = ($now - $uploadInfo.LastUpdateTime).TotalSeconds
            $shouldUpdate = $timeSinceLastUpdate -ge 10 -or $writeResult.Complete

            if ($shouldUpdate) {
                $finalPath = Join-Path $uploadInfo.TargetPhysicalPath $uploadInfo.FileName
                if ($Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath]) {
                    # Use BytesCommitted (disk-flushed bytes) for safe resume point
                    $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Metrics.BytesTransferred = $uploadInfo.BytesCommitted
                    $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Metrics.LastUpdateTime = $now
                }
                $uploadInfo.LastUpdateTime = $now

                $percentComplete = [math]::Round(($uploadInfo.BytesCommitted / $uploadInfo.FileSize) * 100, 1)
                Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Streaming upload progress: $percentComplete% ($($uploadInfo.BytesCommitted) bytes committed)" -Data @{
                    UserID = $uploadInfo.UserID
                    Guid = $guid
                    BytesCommitted = $uploadInfo.BytesCommitted
                    FileSize = $uploadInfo.FileSize
                }
            }

            # Check if complete
            if ($writeResult.Complete) {
                break
            }
        }

        # Close upload session
        $closeResult = & $saveUploadScript -Action 'Close' -UploadGuid $guid

        if (-not $closeResult.Success) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Failed to close upload: $($closeResult.Message)"
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 500 -JsonContent $json
            return
        }

        # Move temp file to final location
        $finalPath = Join-Path $uploadInfo.TargetPhysicalPath $uploadInfo.FileName

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Moving temp file to final location" -Data @{
            TempPath = $uploadInfo.TempFilePath
            FinalPath = $finalPath
            Guid = $guid
        }

        # Ensure target directory exists
        $targetDir = [System.IO.Path]::GetDirectoryName($finalPath)
        if (-not (Test-Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }

        # Handle existing file (overwrite)
        if (Test-Path $finalPath) {
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Removing existing file before move" -Data @{
                Path = $finalPath
                Guid = $guid
            }
            Remove-Item -Path $finalPath -Force -ErrorAction Stop
        }

        # Move file
        Move-Item -Path $uploadInfo.TempFilePath -Destination $finalPath -Force -ErrorAction Stop

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "File moved successfully" -Data @{
            FinalPath = $finalPath
            Guid = $guid
        }

        # Calculate stats
        $duration = (Get-Date).Subtract($startTime).TotalSeconds
        $speedMBps = if ($duration -gt 0) {
            [math]::Round(($totalBytesRead / 1024 / 1024) / $duration, 2)
        } else {
            0
        }

        # Finalize FileTransfers metadata
        if ($Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath]) {
            $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Metrics.Status = 'completed'
            $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Metrics.BytesTransferred = $totalBytesRead
            $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Summary.Completed = Get-Date
            $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Summary.Duration = $duration
            $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Summary.AverageSpeed = $speedMBps
            $Global:PSWebServer.FileTransfers[$uploadInfo.UserID][$finalPath].Summary.Success = $true
        }

        # Cleanup upload metadata
        $Global:PSWebServer.Uploads.Remove($guid) | Out-Null

        # Return success
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload complete' -Data @{
            fileName = $uploadInfo.FileName
            fileSize = $uploadInfo.FileSize
            bytesReceived = $totalBytesRead
            durationSeconds = [math]::Round($duration, 2)
            speedMBps = $speedMBps
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json

    } catch {
        # Error during streaming - abort upload
        $errorDetails = $_.Exception.Message
        $errorLine = $_.InvocationInfo.ScriptLineNumber
        $errorCommand = $_.InvocationInfo.Line.Trim()

        Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Streaming upload error at line ${errorLine}: $errorDetails" -Data @{
            Guid = $guid
            ErrorLine = $errorLine
            ErrorCommand = $errorCommand
            FullError = $_ | Out-String
        }

        & $saveUploadScript -Action 'Abort' -UploadGuid $guid | Out-Null
        $Global:PSWebServer.Uploads.Remove($guid) | Out-Null

        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload failed at line ${errorLine}: $errorDetails"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 500 -JsonContent $json
    }

} catch {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Unexpected error: $($_.Exception.Message)"
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 500 -JsonContent $json
}
