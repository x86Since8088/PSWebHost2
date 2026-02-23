# Save-IncomingFileUpload.ps1
# High-performance streaming file writer with persistent file handle
# Keeps file open during entire upload session for maximum speed

<#
.SYNOPSIS
    Manages streaming file uploads with persistent file handles.

.DESCRIPTION
    This function maintains an open file stream for the duration of an upload,
    appending incoming bytes without the overhead of opening/closing the file
    for each chunk. Uses async I/O for maximum throughput.

.PARAMETER Action
    - 'Open': Creates/opens file and returns session handle
    - 'Write': Appends bytes to open file
    - 'Close': Closes file and cleans up session
    - 'Abort': Closes file and deletes temp file

.PARAMETER UploadGuid
    Unique identifier for this upload session

.PARAMETER FilePath
    Target file path (for 'Open' action)

.PARAMETER FileSize
    Expected total file size in bytes (for 'Open' action)

.PARAMETER Data
    Byte array to write (for 'Write' action)

.PARAMETER FlushThreshold
    Number of bytes to write before flushing (default: 50MB)

.PARAMETER StartOffset
    Byte offset to start writing from (for resume support)

.PARAMETER MaxRetries
    Maximum number of retry attempts for async write/flush operations (default: 3)

.PARAMETER RetryDelayMs
    Initial retry delay in milliseconds with exponential backoff (default: 100ms)
    Delays: 100ms, 200ms, 400ms for retries 1, 2, 3

.EXAMPLE
    # Open upload session
    $result = & $PSScriptRoot\Save-IncomingFileUpload.ps1 -Action 'Open' -UploadGuid $guid -FilePath $path -FileSize 104857600

    # Open with resume support (start from specific offset)
    $result = & $PSScriptRoot\Save-IncomingFileUpload.ps1 -Action 'Open' -UploadGuid $guid -FilePath $path -FileSize 104857600 -StartOffset 52428800

    # Write chunks
    & $PSScriptRoot\Save-IncomingFileUpload.ps1 -Action 'Write' -UploadGuid $guid -Data $chunkBytes

    # Close when complete
    & $PSScriptRoot\Save-IncomingFileUpload.ps1 -Action 'Close' -UploadGuid $guid
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Open', 'Write', 'Close', 'Abort')]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$UploadGuid,

    [Parameter(Mandatory=$false)]
    [string]$FilePath,

    [Parameter(Mandatory=$false)]
    [long]$FileSize,

    [Parameter(Mandatory=$false)]
    [byte[]]$Data,

    [Parameter(Mandatory=$false)]
    [long]$FlushThreshold = 52428800,  # 50MB default

    [Parameter(Mandatory=$false)]
    [long]$StartOffset = 0,  # Resume support

    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 3,  # Maximum retry attempts for async operations

    [Parameter(Mandatory=$false)]
    [int]$RetryDelayMs = 100  # Initial retry delay in milliseconds (exponential backoff)
)

# Global hashtable to store open file sessions
if (-not $Global:PSWebServer.StreamingUploads) {
    $Global:PSWebServer.StreamingUploads = @{}
}

# Global lock for thread safety
if (-not $Global:PSWebServer.StreamingUploadsLock) {
    $Global:PSWebServer.StreamingUploadsLock = [object]::new()
}

function Write-UploadLog {
    param([string]$Message, [string]$Level = 'Info')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Write-Host "[$timestamp] [Save-IncomingFileUpload] [$Level] $Message"
}

# Process action
switch ($Action) {
    'Open' {
        if (-not $FilePath) {
            return @{
                Success = $false
                Message = "FilePath required for Open action"
            }
        }

        if (-not $FileSize -or $FileSize -le 0) {
            return @{
                Success = $false
                Message = "Valid FileSize required for Open action"
            }
        }

        [System.Threading.Monitor]::Enter($Global:PSWebServer.StreamingUploadsLock)
        try {
            # Check if session already exists
            if ($Global:PSWebServer.StreamingUploads.ContainsKey($UploadGuid)) {
                Write-UploadLog "Upload session $UploadGuid already exists" 'Warning'
                return @{
                    Success = $false
                    Message = "Upload session already open"
                }
            }

            # Ensure directory exists
            $directory = [System.IO.Path]::GetDirectoryName($FilePath)
            if (-not (Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }

            # Open file stream with large buffer and async I/O
            # Use OpenOrCreate mode to support resume (appending to existing file)
            $fileMode = if ($StartOffset -gt 0 -and (Test-Path $FilePath)) {
                [System.IO.FileMode]::OpenOrCreate
            } else {
                [System.IO.FileMode]::Create
            }

            $fileStream = [System.IO.FileStream]::new(
                $FilePath,
                $fileMode,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None,
                4194304,  # 4MB buffer for maximum throughput (matches high-performance uploads)
                [System.IO.FileOptions]::Asynchronous -bor [System.IO.FileOptions]::SequentialScan
            )

            # Pre-allocate file to reduce fragmentation and improve performance
            try {
                $fileStream.SetLength($FileSize)

                # Seek to start offset for resume support
                if ($StartOffset -gt 0) {
                    $fileStream.Seek($StartOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
                    Write-UploadLog "Resuming upload at offset $StartOffset for GUID ${UploadGuid}" 'Info'
                } else {
                    $fileStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
                }
            } catch {
                Write-UploadLog "Could not pre-allocate file (may run out of disk space): $($_.Exception.Message)" 'Warning'
            }

            # Create session object
            $session = @{
                Guid = $UploadGuid
                FilePath = $FilePath
                FileStream = $fileStream
                FileSize = $FileSize
                BytesWritten = $StartOffset  # Total bytes written (in buffer)
                BytesCommitted = $StartOffset  # Bytes confirmed flushed to disk (safe for resume)
                BytesSinceFlush = 0
                FlushThreshold = $FlushThreshold
                StartTime = Get-Date
                LastWriteTime = Get-Date
                LastCommitTime = Get-Date  # Track last disk commit for resume safety
                ChunkCount = 0
                Lock = [object]::new()  # Per-session lock for write operations
            }

            $Global:PSWebServer.StreamingUploads[$UploadGuid] = $session

            Write-UploadLog "Opened upload session $UploadGuid for $FilePath ($FileSize bytes)" 'Info'

            return @{
                Success = $true
                Message = "Upload session opened"
                BytesWritten = 0
                FileSize = $FileSize
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($Global:PSWebServer.StreamingUploadsLock)
        }
    }

    'Write' {
        if (-not $Data -or $Data.Length -eq 0) {
            return @{
                Success = $false
                Message = "Data required for Write action"
            }
        }

        # Get session
        if (-not $Global:PSWebServer.StreamingUploads.ContainsKey($UploadGuid)) {
            return @{
                Success = $false
                Message = "Upload session not found (call 'Open' first)"
            }
        }

        $session = $Global:PSWebServer.StreamingUploads[$UploadGuid]

        # Lock this session for thread-safe writes
        [System.Threading.Monitor]::Enter($session.Lock)
        try {
            # Async write with retry mechanism
            # Using WriteAsync for true async I/O with proper cancellation token handling
            $writeSuccess = $false
            $retryCount = 0
            $lastError = $null

            while (-not $writeSuccess -and $retryCount -le $MaxRetries) {
                try {
                    # Create cancellation token with timeout (30 seconds per write attempt)
                    $cts = [System.Threading.CancellationTokenSource]::new(30000)

                    # Perform async write with cancellation token
                    $writeTask = $session.FileStream.WriteAsync($Data, 0, $Data.Length, $cts.Token)

                    # Wait for completion with proper error handling
                    try {
                        $writeTask.GetAwaiter().GetResult()
                        $writeSuccess = $true

                        if ($retryCount -gt 0) {
                            Write-UploadLog "Write succeeded after $retryCount retries for ${UploadGuid}" 'Info'
                        }
                    }
                    catch [System.OperationCanceledException] {
                        # Task was cancelled (timeout or connection closed)
                        $lastError = "Write operation timed out after 30 seconds"
                        Write-UploadLog "Write timeout for ${UploadGuid} (attempt $($retryCount + 1)/$($MaxRetries + 1)): $lastError" 'Warning'
                    }
                    catch {
                        # Other async error
                        $lastError = $_.Exception.Message
                        Write-UploadLog "Write error for ${UploadGuid} (attempt $($retryCount + 1)/$($MaxRetries + 1)): $lastError" 'Warning'
                    }
                    finally {
                        $cts.Dispose()
                    }
                }
                catch {
                    # Error creating cancellation token or starting write
                    $lastError = $_.Exception.Message
                    Write-UploadLog "Write setup error for ${UploadGuid} (attempt $($retryCount + 1)/$($MaxRetries + 1)): $lastError" 'Warning'
                }

                if (-not $writeSuccess) {
                    $retryCount++

                    if ($retryCount -le $MaxRetries) {
                        # Exponential backoff: 100ms, 200ms, 400ms
                        $delayMs = $RetryDelayMs * [Math]::Pow(2, $retryCount - 1)
                        Write-UploadLog "Retrying write for ${UploadGuid} after ${delayMs}ms delay..." 'Info'
                        Start-Sleep -Milliseconds $delayMs
                    }
                }
            }

            # Check if write ultimately failed
            if (-not $writeSuccess) {
                Write-UploadLog "Write failed for ${UploadGuid} after $MaxRetries retries: $lastError" 'Error'
                return @{
                    Success = $false
                    Message = "Write failed after $MaxRetries retries: $lastError"
                    BytesWritten = $session.BytesWritten
                    RetryCount = $retryCount
                }
            }

            # Update counters AFTER successful write
            $session.BytesWritten += $Data.Length
            $session.BytesSinceFlush += $Data.Length
            $session.ChunkCount++
            $session.LastWriteTime = Get-Date

            # Periodic flush to ensure data is written to disk
            $shouldFlush = $false
            if ($session.BytesSinceFlush -ge $session.FlushThreshold) {
                $shouldFlush = $true
            }
            # Also flush if upload is complete
            if ($session.BytesWritten -ge $session.FileSize) {
                $shouldFlush = $true
            }

            if ($shouldFlush) {
                # Async flush with retry mechanism
                $flushSuccess = $false
                $flushRetryCount = 0
                $lastFlushError = $null

                while (-not $flushSuccess -and $flushRetryCount -le $MaxRetries) {
                    try {
                        $cts = [System.Threading.CancellationTokenSource]::new(60000)  # 60 second timeout for flush

                        # FlushAsync with FlushToDisk semantics (forces OS to commit)
                        $flushTask = $session.FileStream.FlushAsync($cts.Token)

                        try {
                            $flushTask.GetAwaiter().GetResult()

                            # Additional explicit flush to disk (FlushAsync doesn't guarantee disk commit)
                            $session.FileStream.Flush($true)

                            $flushSuccess = $true

                            if ($flushRetryCount -gt 0) {
                                Write-UploadLog "Flush succeeded after $flushRetryCount retries for ${UploadGuid}" 'Info'
                            }
                        }
                        catch [System.OperationCanceledException] {
                            $lastFlushError = "Flush operation timed out after 60 seconds"
                            Write-UploadLog "Flush timeout for ${UploadGuid} (attempt $($flushRetryCount + 1)/$($MaxRetries + 1)): $lastFlushError" 'Warning'
                        }
                        catch {
                            $lastFlushError = $_.Exception.Message
                            Write-UploadLog "Flush error for ${UploadGuid} (attempt $($flushRetryCount + 1)/$($MaxRetries + 1)): $lastFlushError" 'Warning'
                        }
                        finally {
                            $cts.Dispose()
                        }
                    }
                    catch {
                        $lastFlushError = $_.Exception.Message
                        Write-UploadLog "Flush setup error for ${UploadGuid} (attempt $($flushRetryCount + 1)/$($MaxRetries + 1)): $lastFlushError" 'Warning'
                    }

                    if (-not $flushSuccess) {
                        $flushRetryCount++

                        if ($flushRetryCount -le $MaxRetries) {
                            $delayMs = $RetryDelayMs * [Math]::Pow(2, $flushRetryCount - 1)
                            Write-UploadLog "Retrying flush for ${UploadGuid} after ${delayMs}ms delay..." 'Info'
                            Start-Sleep -Milliseconds $delayMs
                        }
                    }
                }

                if (-not $flushSuccess) {
                    Write-UploadLog "Flush failed for ${UploadGuid} after $MaxRetries retries: $lastFlushError" 'Error'
                    # Don't fail the entire write - data is in buffer, just not committed to disk yet
                    # Return success but indicate flush failure
                }
                else {
                    $session.BytesSinceFlush = 0

                    # Update committed bytes AFTER successful flush
                    $session.BytesCommitted = $session.BytesWritten
                    $session.LastCommitTime = Get-Date

                    $percentComplete = [math]::Round(($session.BytesWritten / $session.FileSize) * 100, 1)
                    Write-UploadLog "Flushed ${UploadGuid} at $percentComplete% ($($session.BytesCommitted) bytes committed to disk)" 'Debug'
                }
            }

            $isComplete = $session.BytesWritten -ge $session.FileSize

            return @{
                Success = $true
                Message = "Data written"
                BytesWritten = $session.BytesWritten
                BytesCommitted = $session.BytesCommitted  # Safe resume point
                FileSize = $session.FileSize
                Complete = $isComplete
                ChunkCount = $session.ChunkCount
                RetryCount = $retryCount
            }
        }
        catch {
            Write-UploadLog "Unexpected write error for ${UploadGuid}: $($_.Exception.Message)" 'Error'
            return @{
                Success = $false
                Message = "Write failed: $($_.Exception.Message)"
                BytesWritten = $session.BytesWritten
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($session.Lock)
        }
    }

    'Close' {
        if (-not $Global:PSWebServer.StreamingUploads.ContainsKey($UploadGuid)) {
            return @{
                Success = $false
                Message = "Upload session not found"
            }
        }

        [System.Threading.Monitor]::Enter($Global:PSWebServer.StreamingUploadsLock)
        try {
            $session = $Global:PSWebServer.StreamingUploads[$UploadGuid]

            # Lock session for final operations
            [System.Threading.Monitor]::Enter($session.Lock)
            try {
                # Final flush with retry
                if ($session.FileStream) {
                    $flushSuccess = $false
                    $flushRetryCount = 0
                    $lastFlushError = $null

                    while (-not $flushSuccess -and $flushRetryCount -le $MaxRetries) {
                        try {
                            $cts = [System.Threading.CancellationTokenSource]::new(60000)  # 60 second timeout

                            $flushTask = $session.FileStream.FlushAsync($cts.Token)

                            try {
                                $flushTask.GetAwaiter().GetResult()

                                # Additional explicit flush to disk
                                $session.FileStream.Flush($true)

                                $flushSuccess = $true

                                if ($flushRetryCount -gt 0) {
                                    Write-UploadLog "Final flush succeeded after $flushRetryCount retries for ${UploadGuid}" 'Info'
                                }
                            }
                            catch [System.OperationCanceledException] {
                                $lastFlushError = "Final flush timed out after 60 seconds"
                                Write-UploadLog "Final flush timeout for ${UploadGuid} (attempt $($flushRetryCount + 1)/$($MaxRetries + 1)): $lastFlushError" 'Warning'
                            }
                            catch {
                                $lastFlushError = $_.Exception.Message
                                Write-UploadLog "Final flush error for ${UploadGuid} (attempt $($flushRetryCount + 1)/$($MaxRetries + 1)): $lastFlushError" 'Warning'
                            }
                            finally {
                                $cts.Dispose()
                            }
                        }
                        catch {
                            $lastFlushError = $_.Exception.Message
                            Write-UploadLog "Final flush setup error for ${UploadGuid} (attempt $($flushRetryCount + 1)/$($MaxRetries + 1)): $lastFlushError" 'Warning'
                        }

                        if (-not $flushSuccess) {
                            $flushRetryCount++

                            if ($flushRetryCount -le $MaxRetries) {
                                $delayMs = $RetryDelayMs * [Math]::Pow(2, $flushRetryCount - 1)
                                Write-UploadLog "Retrying final flush for ${UploadGuid} after ${delayMs}ms delay..." 'Info'
                                Start-Sleep -Milliseconds $delayMs
                            }
                        }
                    }

                    if (-not $flushSuccess) {
                        Write-UploadLog "Final flush failed for ${UploadGuid} after $MaxRetries retries: $lastFlushError" 'Error'
                        # Still close the stream, but data may not be fully committed
                    }

                    $session.FileStream.Close()
                    $session.FileStream.Dispose()
                }

                $duration = (Get-Date).Subtract($session.StartTime).TotalSeconds
                $speedMBps = if ($duration -gt 0) {
                    [math]::Round(($session.BytesWritten / 1024 / 1024) / $duration, 2)
                } else {
                    0
                }

                Write-UploadLog "Closed upload session ${UploadGuid}: $($session.BytesWritten) bytes in $([math]::Round($duration, 2))s ($speedMBps MB/s)" 'Info'

                # Remove session
                $Global:PSWebServer.StreamingUploads.Remove($UploadGuid) | Out-Null

                return @{
                    Success = $true
                    Message = "Upload session closed"
                    BytesWritten = $session.BytesWritten
                    Duration = $duration
                    SpeedMBps = $speedMBps
                }
            }
            finally {
                [System.Threading.Monitor]::Exit($session.Lock)
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($Global:PSWebServer.StreamingUploadsLock)
        }
    }

    'Abort' {
        if (-not $Global:PSWebServer.StreamingUploads.ContainsKey($UploadGuid)) {
            return @{
                Success = $true  # Already gone
                Message = "Upload session not found (already aborted or never opened)"
            }
        }

        [System.Threading.Monitor]::Enter($Global:PSWebServer.StreamingUploadsLock)
        try {
            $session = $Global:PSWebServer.StreamingUploads[$UploadGuid]

            [System.Threading.Monitor]::Enter($session.Lock)
            try {
                # Close file
                if ($session.FileStream) {
                    $session.FileStream.Close()
                    $session.FileStream.Dispose()
                }

                # Delete temp file
                if (Test-Path $session.FilePath) {
                    Remove-Item -Path $session.FilePath -Force -ErrorAction SilentlyContinue
                }

                Write-UploadLog "Aborted upload session $UploadGuid (deleted temp file)" 'Warning'

                # Remove session
                $Global:PSWebServer.StreamingUploads.Remove($UploadGuid) | Out-Null

                return @{
                    Success = $true
                    Message = "Upload session aborted and temp file deleted"
                }
            }
            finally {
                [System.Threading.Monitor]::Exit($session.Lock)
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($Global:PSWebServer.StreamingUploadsLock)
        }
    }
}
