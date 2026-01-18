param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message, $data = @{}) {
    $result = @{ status = $status; message = $message }
    if ($data.Count -gt 0) {
        $result.data = $data
    }
    return $result | ConvertTo-Json -Depth 5
}

# Get user ID from session
if (-not $sessiondata -or -not $sessiondata.UserID) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'User not authenticated'
    context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

$userID = $sessiondata.UserID

# Read request body
$reader = New-Object System.IO.StreamReader($Request.InputStream)
$body = $reader.ReadToEnd()
$reader.Close()

try {
    $data = $body | ConvertFrom-Json
}
catch {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Invalid JSON in request body'
    context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

# Validate required parameters
if (-not $data.uploadId -or -not $data.fileName -or $null -eq $data.chunkIndex -or $null -eq $data.totalChunks -or -not $data.chunkData) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Missing required parameters: uploadId, fileName, chunkIndex, totalChunks, chunkData'
    context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
    return
}

# Get user's file-explorer folder
$getUserDataScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\UserData_Folder_Get.ps1"
if (-not (Test-Path $getUserDataScript)) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'UserData_Folder_Get.ps1 not found'
    context_response -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Get user folder
    $userFolder = & $getUserDataScript -UserID $userID -Application "file-explorer"

    if (-not $userFolder) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Failed to get user data folder'
        context_response -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Create temp directory for chunks
    $tempRoot = Join-Path $userFolder ".temp"
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
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Invalid base64 chunk data'
        context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
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

        # Assemble file from chunks
        $targetPath = $data.path -replace '^/', ''
        $targetFolder = if ($targetPath) {
            & $getUserDataScript -UserID $userID -Application "file-explorer" -SubFolder $targetPath -CreateIfMissing
        } else {
            $userFolder
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

        $responseData = @{
            status = 'success'
            message = 'Upload completed successfully'
            fileName = $data.fileName
            size = $finalFileInfo.Length
            complete = $true
        }
        $jsonResponse = $responseData | ConvertTo-Json -Compress
        context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
    }
    else {
        # More chunks needed
        $responseData = @{
            status = 'success'
            message = 'Chunk received'
            chunkIndex = $data.chunkIndex
            received = $receivedChunks.Count
            total = $data.totalChunks
            complete = $false
        }
        $jsonResponse = $responseData | ConvertTo-Json -Compress
        context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
    }
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error in chunked upload: $($_.Exception.Message)" -Data @{
        UserID = $userID
        UploadId = $data.uploadId
        ChunkIndex = $data.chunkIndex
    }

    # Cleanup on error
    $uploadTempDir = Join-Path (Join-Path $userFolder ".temp") $data.uploadId
    if (Test-Path $uploadTempDir) {
        Remove-Item -Path $uploadTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
