param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Check for existing incomplete uploads before starting new upload

.DESCRIPTION
    POST /api/v1/files/upload-check
    Body: { fileName, fileSize, targetPath }

    Checks if there's an existing incomplete upload that matches the file.
    Returns resume info if found, allowing user to choose resume or start fresh.

.EXAMPLE
    POST /api/v1/files/upload-check
    Body: { "fileName": "video.mp4", "fileSize": 104857600, "targetPath": "/" }
    Response: { status: 'success', data: { canResume: true, uploadGuid: '...', bytesUploaded: 52428800 } }
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

try {
    # Parse JSON body
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

    Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Checking for existing uploads of $fileName ($fileSize bytes)" -Data @{
        UserID = $userID
        FileName = $fileName
        FileSize = $fileSize
        TargetPath = $targetPath
    }

    # Check temp directories for matching uploads
    $tempDir = Join-Path $Global:PSWebServer.Project_Root.Path "uploads\temp"
    $matchingUploads = @()

    if (Test-Path $tempDir) {
        # Look for streamUpload_*.tmp files
        $streamTempFiles = Get-ChildItem -Path $tempDir -Filter "streamUpload_*.tmp" -ErrorAction SilentlyContinue

        foreach ($tempFile in $streamTempFiles) {
            # Extract GUID from filename
            if ($tempFile.Name -match 'streamUpload_([0-9a-f-]+)\.tmp') {
                $guid = $matches[1]

                # Check if this upload exists in Uploads hashtable
                if ($Global:PSWebServer.Uploads -and $Global:PSWebServer.Uploads.ContainsKey($guid)) {
                    $uploadInfo = $Global:PSWebServer.Uploads[$guid]

                    # Match by filename, filesize, and user
                    if ($uploadInfo.FileName -eq $fileName -and
                        $uploadInfo.FileSize -eq $fileSize -and
                        $uploadInfo.UserID -eq $userID) {

                        $matchingUploads += @{
                            uploadGuid = $guid
                            fileName = $uploadInfo.FileName
                            fileSize = $uploadInfo.FileSize
                            bytesCommitted = $uploadInfo.BytesCommitted
                            bytesReceived = $uploadInfo.BytesReceived
                            tempFilePath = $uploadInfo.TempFilePath
                            startTime = $uploadInfo.StartTime
                            uploadMethod = 'streaming'
                            percentComplete = [math]::Round(($uploadInfo.BytesCommitted / $uploadInfo.FileSize) * 100, 1)
                        }
                    }
                }
                # Also check orphaned temp files (upload metadata lost but file exists)
                else {
                    # Get file size to compare
                    $tempFileSize = $tempFile.Length

                    # If file exists and might match (within reasonable size range)
                    if ($tempFileSize -gt 0 -and $tempFileSize -lt $fileSize) {
                        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Found orphaned temp file: $($tempFile.Name)" -Data @{
                            UserID = $userID
                            Guid = $guid
                            TempFileSize = $tempFileSize
                            ExpectedSize = $fileSize
                        }

                        # We can offer resume but need to create new upload metadata
                        $matchingUploads += @{
                            uploadGuid = $guid
                            fileName = $fileName  # Use provided filename
                            fileSize = $fileSize
                            bytesCommitted = $tempFileSize
                            bytesReceived = $tempFileSize
                            tempFilePath = $tempFile.FullName
                            orphaned = $true
                            uploadMethod = 'streaming'
                            percentComplete = [math]::Round(($tempFileSize / $fileSize) * 100, 1)
                        }
                    }
                }
            }
        }
    }

    # Check for chunked upload temp files (newUploadTemp_*.tmp)
    $roles = $sessiondata.Roles
    $targetResult = Resolve-WebHostFileExplorerPath -LogicalPath $targetPath -UserID $userID -Roles $roles -Response $Response -RequiredPermission 'write'
    if ($targetResult) {
        $chunkTempFiles = Get-ChildItem -Path $targetResult.PhysicalPath -Filter "newUploadTemp_*.tmp" -ErrorAction SilentlyContinue

        foreach ($tempFile in $chunkTempFiles) {
            if ($tempFile.Name -match 'newUploadTemp_([0-9a-f-]+)\.tmp') {
                $guid = $matches[1]

                # Check if this upload exists in Uploads hashtable
                if ($Global:PSWebServer.Uploads -and $Global:PSWebServer.Uploads.ContainsKey($guid)) {
                    $uploadInfo = $Global:PSWebServer.Uploads[$guid]

                    if ($uploadInfo.FileName -eq $fileName -and
                        $uploadInfo.FileSize -eq $fileSize -and
                        $uploadInfo.UserID -eq $userID) {

                        $matchingUploads += @{
                            uploadGuid = $guid
                            fileName = $uploadInfo.FileName
                            fileSize = $uploadInfo.FileSize
                            bytesReceived = $uploadInfo.ReceivedBytes
                            receivedChunks = $uploadInfo.ReceivedChunks
                            totalChunks = $uploadInfo.TotalChunks
                            tempFilePath = $uploadInfo.TempFilePath
                            startTime = $uploadInfo.CreatedAt
                            uploadMethod = 'chunked'
                            percentComplete = [math]::Round(($uploadInfo.ReceivedChunks / $uploadInfo.TotalChunks) * 100, 1)
                        }
                    }
                }
            }
        }
    }

    if ($matchingUploads.Count -gt 0) {
        # Found existing upload(s)
        $mostRecentUpload = $matchingUploads | Sort-Object { if ($_.startTime) { $_.startTime } else { [DateTime]::MinValue } } -Descending | Select-Object -First 1

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Found existing upload for $fileName" -Data @{
            UserID = $userID
            UploadGuid = $mostRecentUpload.uploadGuid
            BytesCommitted = $mostRecentUpload.bytesCommitted
            PercentComplete = $mostRecentUpload.percentComplete
        }

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Existing upload found' -Data @{
            canResume = $true
            upload = $mostRecentUpload
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
    else {
        # No existing upload found
        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "No existing upload found for $fileName" -Data @{
            UserID = $userID
        }

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'No existing upload found' -Data @{
            canResume = $false
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        FileName = $fileName
    }
}
