param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Dot-source File Explorer helper functions with hot-reloading support
$helperPath = Join-Path $PSScriptRoot "..\..\..\..\..\modules\FileExplorerHelper.ps1"
$helperInfo = Get-Item $helperPath -ErrorAction Stop
$cacheKey = 'FileExplorerHelper_LastWrite'

# Always dot-source on first run, or if file has been updated
$cachedTime = $Global:PSWebServer[$cacheKey]
$needsLoad = (-not $cachedTime) -or ($cachedTime -lt $helperInfo.LastWriteTime)

if ($needsLoad) {
    # Dot-source the file to load functions into current scope
    . $helperPath
    $Global:PSWebServer[$cacheKey] = $helperInfo.LastWriteTime
    Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Loaded FileExplorerHelper.ps1 (LastWrite: $($helperInfo.LastWriteTime))"
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

# Validate required parameters
if (-not $data.uploadId -or -not $data.fileName -or $null -eq $data.chunkIndex -or $null -eq $data.totalChunks -or -not $data.chunkData) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameters: uploadId, fileName, chunkIndex, totalChunks, chunkData'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Get user's personal storage for temp chunks (always use personal storage for temp files)
    $tempStorageResult = Resolve-WebHostFileExplorerPath -LogicalPath "User:me" -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
    if (-not $tempStorageResult) { return }

    # Create temp directory for chunks in personal storage
    $tempRoot = Join-Path $tempStorageResult.PhysicalPath ".temp"
    if (-not (Test-Path $tempRoot)) {
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    }

    $uploadTempDir = Join-Path $tempRoot $data.uploadId
    if (-not (Test-Path $uploadTempDir)) {
        New-Item -Path $uploadTempDir -ItemType Directory -Force | Out-Null
    }

    # Decode base64 chunk data
    try {
        $chunkBytes = [System.Convert]::FromBase64String($data.chunkData)
    }
    catch {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Invalid base64 chunk data'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Save chunk
    $chunkPath = Join-Path $uploadTempDir "chunk_$($data.chunkIndex)"
    [System.IO.File]::WriteAllBytes($chunkPath, $chunkBytes)

    Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Chunk received: $($data.chunkIndex)/$($data.totalChunks)" -Data @{
        UserID = $userID
        UploadId = $data.uploadId
        FileName = $data.fileName
        ChunkSize = $chunkBytes.Length
    }

    # Check if all chunks received
    $receivedChunks = Get-ChildItem -Path $uploadTempDir -Filter "chunk_*" | Sort-Object Name
    $allChunksReceived = $receivedChunks.Count -eq $data.totalChunks

    if ($allChunksReceived) {
        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "All chunks received, assembling file: $($data.fileName)" -Data @{
            UserID = $userID
            UploadId = $data.uploadId
            TotalChunks = $data.totalChunks
        }

        # Assemble file from chunks - resolve target logical path
        $targetLogicalPath = if ($data.path) { $data.path } else { "User:me" }

        # Resolve target path with write permission
        $targetResult = Resolve-WebHostFileExplorerPath -LogicalPath $targetLogicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
        if (-not $targetResult) { return }

        $targetFolder = $targetResult.PhysicalPath

        # Create target folder if it doesn't exist
        if (-not (Test-Path $targetFolder)) {
            New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
        }

        $finalFilePath = Join-Path $targetFolder $data.fileName
        $outputStream = [System.IO.File]::OpenWrite($finalFilePath)

        try {
            for ($i = 0; $i -lt $data.totalChunks; $i++) {
                $chunkFile = Join-Path $uploadTempDir "chunk_$i"
                if (Test-Path $chunkFile) {
                    $chunkContent = [System.IO.File]::ReadAllBytes($chunkFile)
                    $outputStream.Write($chunkContent, 0, $chunkContent.Length)
                }
                else {
                    throw "Missing chunk: $i"
                }
            }
        }
        finally {
            $outputStream.Close()
        }

        # Cleanup temp directory
        Remove-Item -Path $uploadTempDir -Recurse -Force -ErrorAction SilentlyContinue

        # Get final file info
        $finalFileInfo = Get-Item $finalFilePath

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Chunked upload completed: $($data.fileName)" -Data @{
            UserID = $userID
            UploadId = $data.uploadId
            Size = $finalFileInfo.Length
            Chunks = $data.totalChunks
        }

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Upload completed successfully' -Data @{
            fileName = $data.fileName
            size = $finalFileInfo.Length
            complete = $true
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
    else {
        # More chunks needed
        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Chunk received' -Data @{
            chunkIndex = $data.chunkIndex
            received = $receivedChunks.Count
            total = $data.totalChunks
            complete = $false
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
    }
}
catch {
    # Cleanup on error
    if ($tempRoot) {
        $uploadTempDir = Join-Path $tempRoot $data.uploadId
        if (Test-Path $uploadTempDir) {
            Remove-Item -Path $uploadTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        UploadId = $data.uploadId
        ChunkIndex = $data.chunkIndex
    }
}
