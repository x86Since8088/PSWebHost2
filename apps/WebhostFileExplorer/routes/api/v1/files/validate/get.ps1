param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Validate file integrity using SHA256 hash with optional range support

.DESCRIPTION
    GET /api/v1/files/validate?guid=XXXX
    GET /api/v1/files/validate?path=/path/to/file

    Computes SHA256 hash of file (or range) for validation.
    Supports Range header for partial file hashing.
    Handles files open for writing gracefully (returns retry-after).

.EXAMPLE
    GET /api/v1/files/validate?guid=550e8400-e29b-41d4-a716-446655440000
    Response: { status: 'success', data: { sha256: '...', fileSize: 12345 } }

.EXAMPLE
    GET /api/v1/files/validate?guid=550e8400-e29b-41d4-a716-446655440000
    Range: bytes=0-1048575
    Response: { status: 'success', data: { sha256: '...', rangeStart: 0, rangeEnd: 1048575 } }
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

$roles = $sessiondata.Roles

try {
    # Get file identifier (GUID or path)
    $guid = $Request.QueryString['guid']
    $filePath = $Request.QueryString['path']

    if (-not $guid -and -not $filePath) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: guid or path'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Resolve file path
    $physicalPath = $null
    $fileInfo = $null

    if ($guid) {
        # Check active uploads first
        if ($Global:PSWebServer.Uploads -and $Global:PSWebServer.Uploads.ContainsKey($guid)) {
            $uploadInfo = $Global:PSWebServer.Uploads[$guid]

            # Verify user owns this upload
            if ($uploadInfo.UserID -ne $userID) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Unauthorized: You do not own this upload'
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
                return
            }

            # Use temp file path
            $physicalPath = $uploadInfo.TempFilePath
        }
        # Check completed uploads (FileTransfers)
        elseif ($Global:PSWebServer.FileTransfers -and $Global:PSWebServer.FileTransfers[$userID]) {
            # Search for upload GUID in FileTransfers
            $foundTransfer = $null
            foreach ($transferPath in $Global:PSWebServer.FileTransfers[$userID].Keys) {
                $transfer = $Global:PSWebServer.FileTransfers[$userID][$transferPath]
                if ($transfer.SessionID -eq $guid) {
                    $foundTransfer = $transfer
                    $physicalPath = $transfer.LocalPath
                    break
                }
            }

            if (-not $foundTransfer) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload not found: $guid"
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
                return
            }
        }
        else {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload not found: $guid"
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
            return
        }
    }
    else {
        # Use provided path - resolve with permission check
        $resolveResult = Resolve-WebHostFileExplorerPath -LogicalPath $filePath -UserID $userID -Roles $roles -Response $Response -RequiredPermission 'read'
        if (-not $resolveResult) { return }

        $physicalPath = Join-Path $resolveResult.PhysicalPath (Split-Path $filePath -Leaf)
    }

    # Check if file exists
    if (-not (Test-Path $physicalPath)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "File not found: $physicalPath"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    $fileInfo = Get-Item $physicalPath

    # Parse Range header (if present)
    $rangeHeader = $Request.Headers['Range']
    $rangeStart = $null
    $rangeEnd = $null
    $fullFile = $true

    if ($rangeHeader) {
        # Parse Range header: "bytes=START-END"
        if ($rangeHeader -match 'bytes\s*=\s*(\d+)-(\d+)?') {
            $rangeStart = [long]$matches[1]
            $rangeEnd = if ($matches[2]) { [long]$matches[2] } else { $fileInfo.Length - 1 }
            $fullFile = $false

            # Validate range
            if ($rangeStart -lt 0 -or $rangeStart -ge $fileInfo.Length) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Invalid range: start $rangeStart is out of bounds (file size: $($fileInfo.Length))"
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 416 -JsonContent $json
                return
            }

            if ($rangeEnd -ge $fileInfo.Length) {
                $rangeEnd = $fileInfo.Length - 1
            }

            if ($rangeStart -gt $rangeEnd) {
                $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Invalid range: start $rangeStart > end $rangeEnd"
                Send-WebHostFileExplorerResponse -Response $Response -StatusCode 416 -JsonContent $json
                return
            }

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Validating file range: bytes $rangeStart-$rangeEnd" -Data @{
                UserID = $userID
                FilePath = $physicalPath
                RangeStart = $rangeStart
                RangeEnd = $rangeEnd
            }
        }
    }

    # Attempt to open file for reading
    $maxRetries = 3
    $retryDelayMs = 500
    $retryCount = 0
    $fileStream = $null
    $fileOpenSuccess = $false
    $lastError = $null

    while (-not $fileOpenSuccess -and $retryCount -le $maxRetries) {
        try {
            # Try to open with shared read access
            $fileStream = [System.IO.File]::Open(
                $physicalPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite  # Allow reading even if file is open for writing
            )
            $fileOpenSuccess = $true

            if ($retryCount -gt 0) {
                Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "File opened for validation after $retryCount retries" -Data @{
                    UserID = $userID
                    FilePath = $physicalPath
                }
            }
        }
        catch [System.IO.IOException] {
            # File may be locked or in use
            $lastError = $_.Exception.Message

            # Check if file is open for writing (common case)
            if ($lastError -match 'being used by another process' -or $lastError -match 'locked') {
                Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "File locked for validation (attempt $($retryCount + 1)/$($maxRetries + 1)): $lastError" -Data @{
                    UserID = $userID
                    FilePath = $physicalPath
                    Attempt = $retryCount + 1
                }

                $retryCount++

                if ($retryCount -le $maxRetries) {
                    # Exponential backoff
                    $delayMs = $retryDelayMs * [Math]::Pow(2, $retryCount - 1)
                    Start-Sleep -Milliseconds $delayMs
                }
                else {
                    # File is being written to - return retry-after response
                    Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "File still locked after $maxRetries retries, suggesting retry" -Data @{
                        UserID = $userID
                        FilePath = $physicalPath
                    }

                    # Return 409 Conflict with retry-after suggestion
                    $Response.AddHeader('Retry-After', '5')  # Suggest retry in 5 seconds

                    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'File is currently being written to. Please retry in a few seconds.' -Data @{
                        retryAfter = 5
                        fileOpenForWriting = $true
                    }
                    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 409 -JsonContent $json
                    return
                }
            }
            else {
                # Other I/O error
                throw
            }
        }
    }

    if (-not $fileOpenSuccess) {
        throw "Failed to open file after $maxRetries retries: $lastError"
    }

    try {
        # Compute SHA256 hash
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $startTime = Get-Date

        if ($fullFile) {
            # Hash entire file
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Computing SHA256 hash of full file" -Data @{
                UserID = $userID
                FilePath = $physicalPath
                FileSize = $fileInfo.Length
            }

            $hashBytes = $sha256.ComputeHash($fileStream)
        }
        else {
            # Hash only the specified range
            $rangeLength = $rangeEnd - $rangeStart + 1

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Computing SHA256 hash of file range" -Data @{
                UserID = $userID
                FilePath = $physicalPath
                RangeStart = $rangeStart
                RangeEnd = $rangeEnd
                RangeLength = $rangeLength
            }

            # Seek to range start
            $fileStream.Seek($rangeStart, [System.IO.SeekOrigin]::Begin) | Out-Null

            # Read range into memory (for reasonable range sizes)
            if ($rangeLength -gt 100MB) {
                # For large ranges, use streaming hash
                $buffer = New-Object byte[] 4194304  # 4MB buffer
                $bytesRemaining = $rangeLength

                while ($bytesRemaining -gt 0) {
                    $bytesToRead = [Math]::Min($buffer.Length, $bytesRemaining)
                    $bytesRead = $fileStream.Read($buffer, 0, $bytesToRead)

                    if ($bytesRead -eq 0) {
                        break  # End of file
                    }

                    $sha256.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
                    $bytesRemaining -= $bytesRead
                }

                # Finalize hash
                $sha256.TransformFinalBlock(@(), 0, 0) | Out-Null
                $hashBytes = $sha256.Hash
            }
            else {
                # Read entire range into memory
                $rangeBytes = New-Object byte[] $rangeLength
                $fileStream.Read($rangeBytes, 0, $rangeLength) | Out-Null

                $hashBytes = $sha256.ComputeHash($rangeBytes)
            }
        }

        # Convert hash to hex string
        $hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

        $duration = ((Get-Date) - $startTime).TotalSeconds
        $bytesHashed = if ($fullFile) { $fileInfo.Length } else { $rangeEnd - $rangeStart + 1 }
        $hashSpeedMBps = if ($duration -gt 0) { [math]::Round(($bytesHashed / 1024 / 1024) / $duration, 2) } else { 0 }

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "SHA256 hash computed successfully" -Data @{
            UserID = $userID
            FilePath = $physicalPath
            Hash = $hashHex
            BytesHashed = $bytesHashed
            Duration = [math]::Round($duration, 3)
            SpeedMBps = $hashSpeedMBps
        }

        # Build response data
        $responseData = @{
            sha256 = $hashHex
            fileName = $fileInfo.Name
        }

        if ($fullFile) {
            $responseData.fileSize = $fileInfo.Length
            $responseData.fullFile = $true
        }
        else {
            $responseData.rangeStart = $rangeStart
            $responseData.rangeEnd = $rangeEnd
            $responseData.rangeLength = $rangeEnd - $rangeStart + 1
            $responseData.fullFile = $false
        }

        # Include performance stats
        $responseData.hashDuration = [math]::Round($duration, 3)
        $responseData.hashSpeedMBps = $hashSpeedMBps

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Hash computed successfully' -Data $responseData
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
    finally {
        if ($fileStream) {
            $fileStream.Close()
            $fileStream.Dispose()
        }
        if ($sha256) {
            $sha256.Dispose()
        }
    }
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        FilePath = $physicalPath
        Guid = $guid
    }
}
