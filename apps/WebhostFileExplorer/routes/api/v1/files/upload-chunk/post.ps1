param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Initialize or cancel a chunked file upload

.DESCRIPTION
    POST with JSON metadata to initialize upload (returns GUID) or cancel upload

.EXAMPLE
    # Initialize upload
    POST /api/v1/files/upload-chunk
    Body: {
        "action": "init",
        "fileName": "largefile.zip",
        "fileSize": 104857600,
        "chunkSize": 26214400,
        "totalChunks": 4,
        "targetPath": "User:me/Documents"
    }
    Response: {
        "status": "success",
        "guid": "550e8400-e29b-41d4-a716-446655440000",
        "uploadUrl": "/api/v1/files/upload-chunk?guid=..."
    }

.EXAMPLE
    # Cancel upload
    POST /api/v1/files/upload-chunk
    Body: {
        "action": "cancel",
        "guid": "550e8400-e29b-41d4-a716-446655440000"
    }
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

# Read request body
$reader = New-Object System.IO.StreamReader($Request.InputStream)
$body = $reader.ReadToEnd()
$reader.Close()

try {
    $data = $body | ConvertFrom-Json
}
catch {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Invalid JSON in request body'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

# Validate action parameter
if (-not $data.action) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: action (init or cancel)'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

# Initialize global hashtables if needed
if (-not $Global:PSWebServer.Uploads) {
    $Global:PSWebServer.Uploads = [hashtable]::Synchronized(@{})
}
if (-not $Global:PSWebServer.UploadTempFiles) {
    $Global:PSWebServer.UploadTempFiles = [hashtable]::Synchronized(@{})
}
if (-not $Global:PSWebServer.UploadLocks) {
    $Global:PSWebServer.UploadLocks = [hashtable]::Synchronized(@{})
}

try {
    if ($data.action -eq 'init') {
        # ====================================================================
        # INITIALIZE UPLOAD
        # ====================================================================

        # Validate required parameters for init
        if (-not $data.fileName -or $null -eq $data.fileSize -or $null -eq $data.chunkSize -or $null -eq $data.totalChunks) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameters: fileName, fileSize, chunkSize, totalChunks'
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
            return
        }

        # Generate GUID for this upload
        $uploadGuid = [Guid]::NewGuid().ToString()

        # Resolve target path with write permission
        $targetLogicalPath = if ($data.targetPath) { $data.targetPath } else { "User:me" }
        $targetResult = Resolve-WebHostFileExplorerPath -LogicalPath $targetLogicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
        if (-not $targetResult) { return }

        # Create temp file path (direct write instead of chunk files)
        $tempFilePath = Join-Path $targetResult.PhysicalPath "newUploadTemp_$uploadGuid.tmp"

        # Store temp file path in UploadTempFiles hashtable
        $Global:PSWebServer.UploadTempFiles[$uploadGuid] = $tempFilePath

        # Create lock object for synchronized writes
        $lockObj = [PSCustomObject]@{ Lock = $null }
        $Global:PSWebServer.UploadLocks[$uploadGuid] = $lockObj

        # Initialize chunk bitmap for tracking received chunks
        $chunkBitmap = New-Object bool[] $data.totalChunks

        # Determine upload method (optional parameter from frontend)
        $uploadMethod = if ($data.uploadMethod) { $data.uploadMethod } else { 'unknown' }

        # Save upload metadata to global hashtable
        $Global:PSWebServer.Uploads[$uploadGuid] = @{
            Guid = $uploadGuid
            UserID = $userID
            FileName = $data.fileName
            FileSize = [long]$data.fileSize
            ChunkSize = [int]$data.chunkSize
            TotalChunks = [int]$data.totalChunks
            TargetPath = $targetResult.PhysicalPath
            TempFilePath = $tempFilePath  # Direct file instead of directory
            CreatedAt = Get-Date
            ReceivedChunks = 0
            ReceivedBytes = 0
            ChunkBitmap = $chunkBitmap  # Track which chunks received
            LastLogTime = [datetime]::MinValue  # Track last log time for throttling
            UploadMethod = $uploadMethod
        }

        # Persist upload session to database for resume capability
        try {
            $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
            $chunkBitmapJson = $chunkBitmap | ConvertTo-Json -Compress
            $startTime = [int]([DateTimeOffset]::Now).ToUnixTimeSeconds()

            $insertQuery = @"
INSERT INTO Upload_Sessions (
    UploadGuid, UserID, FileName, FileSize, TargetPath, ChunkSize, TotalChunks,
    ChunkBitmap, ReceivedBytes, UploadMethod, TempFilePath, StartTime, LastActivityTime, Status
)
VALUES (
    @UploadGuid, @UserID, @FileName, @FileSize, @TargetPath, @ChunkSize, @TotalChunks,
    @ChunkBitmap, @ReceivedBytes, @UploadMethod, @TempFilePath, @StartTime, @LastActivityTime, @Status
)
"@

            $dbParams = @{
                UploadGuid = $uploadGuid
                UserID = $userID
                FileName = $data.fileName
                FileSize = [long]$data.fileSize
                TargetPath = $targetResult.PhysicalPath
                ChunkSize = [int]$data.chunkSize
                TotalChunks = [int]$data.totalChunks
                ChunkBitmap = $chunkBitmapJson
                ReceivedBytes = 0
                UploadMethod = $uploadMethod
                TempFilePath = $tempFilePath
                StartTime = $startTime
                LastActivityTime = $startTime
                Status = 'active'
            }

            Invoke-SqliteQuery -DataSource $dbFile -Query $insertQuery -SqlParameters $dbParams

            Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Upload session saved to database: $uploadGuid" -Data @{
                Guid = $uploadGuid
                Method = $uploadMethod
            }
        }
        catch {
            Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to save upload session to database (will continue with in-memory only): $($_.Exception.Message)" -Data @{
                Guid = $uploadGuid
                Error = $_.Exception.Message
            }
        }

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Upload initialized: $($data.fileName)" -Data @{
            UserID = $userID
            Guid = $uploadGuid
            FileSize = $data.fileSize
            TotalChunks = $data.totalChunks
            Method = $uploadMethod
        }

        # Initialize FileTransfers metadata structure
        if (-not $Global:PSWebServer.FileTransfers) {
            $Global:PSWebServer.FileTransfers = @{}
        }
        if (-not $Global:PSWebServer.FileTransfers[$userID]) {
            $Global:PSWebServer.FileTransfers[$userID] = [hashtable]::Synchronized(@{})
        }

        $finalPath = Join-Path $targetResult.PhysicalPath $data.fileName
        $Global:PSWebServer.FileTransfers[$userID][$finalPath] = [hashtable]::Synchronized([ordered]@{
            Name = $data.fileName
            RemotePath = $targetLogicalPath
            LocalPath = $finalPath
            SessionID = $uploadGuid
            UserID = $userID
            Metrics = [hashtable]::Synchronized([ordered]@{
                FileSize = [long]$data.fileSize
                BytesTransferred = 0
                ChunksReceived = 0
                TotalChunks = [int]$data.totalChunks
                StartTime = Get-Date
                LastUpdateTime = Get-Date
                Method = 'chunked'
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

        # Return GUID and upload URL
        $uploadUrl = "/apps/WebhostFileExplorer/api/v1/files/upload-chunk?guid=$uploadGuid"
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload initialized' -Data @{
            guid = $uploadGuid
            uploadUrl = $uploadUrl
            fileName = $data.fileName
            fileSize = $data.fileSize
            totalChunks = $data.totalChunks
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
    elseif ($data.action -eq 'cancel') {
        # ====================================================================
        # CANCEL UPLOAD
        # ====================================================================

        # Validate required parameters for cancel
        if (-not $data.guid) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: guid'
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
            return
        }

        # Check if upload exists
        if (-not $Global:PSWebServer.Uploads.ContainsKey($data.guid)) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Upload not found: $($data.guid)"
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
            return
        }

        $uploadInfo = $Global:PSWebServer.Uploads[$data.guid]

        # Verify user owns this upload
        if ($uploadInfo.UserID -ne $userID) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Unauthorized: You do not own this upload'
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
            return
        }

        # Cleanup temp file
        if (Test-Path $uploadInfo.TempFilePath) {
            Remove-Item -Path $uploadInfo.TempFilePath -Force -ErrorAction SilentlyContinue
        }

        # Remove from database
        try {
            $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
            $deleteQuery = "DELETE FROM Upload_Sessions WHERE UploadGuid = @Guid"
            Invoke-SqliteQuery -DataSource $dbFile -Query $deleteQuery -SqlParameters @{ Guid = $data.guid }

            Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Upload session deleted from database: $($data.guid)"
        }
        catch {
            Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to delete upload session from database: $($_.Exception.Message)" -Data @{
                Guid = $data.guid
                Error = $_.Exception.Message
            }
        }

        # Remove from global hashtables
        $Global:PSWebServer.Uploads.Remove($data.guid)
        $Global:PSWebServer.UploadTempFiles.Remove($data.guid)
        $Global:PSWebServer.UploadLocks.Remove($data.guid)

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Upload cancelled: $($uploadInfo.FileName)" -Data @{
            UserID = $userID
            Guid = $data.guid
        }

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload cancelled'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
    else {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Invalid action: $($data.action). Must be 'init' or 'cancel'"
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    }
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        Action = $data.action
    }
}
