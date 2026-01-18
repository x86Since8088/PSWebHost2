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

# Get query parameters
$queryParams = @{}
if ($Request.Url.Query) {
    $Request.Url.Query.TrimStart('?').Split('&') | ForEach-Object {
        $parts = $_.Split('=')
        if ($parts.Length -eq 2) {
            $queryParams[[System.Web.HttpUtility]::UrlDecode($parts[0])] = [System.Web.HttpUtility]::UrlDecode($parts[1])
        }
    }
}

$filePath = $queryParams['path']
$mode = $queryParams['mode'] # 'content', 'metadata', or 'thumbnail'

if (-not $filePath) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Missing path parameter'
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

    # Build full file path and validate
    $fullPath = Join-Path $userFolder $filePath
    $fullPath = [System.IO.Path]::GetFullPath($fullPath)

    # Security: Ensure path is within user folder
    if (-not $fullPath.StartsWith($userFolder.FullName)) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Invalid path - access denied'
        context_response -Response $Response -StatusCode 403 -String $jsonResponse -ContentType "application/json"
        return
    }

    if (-not (Test-Path $fullPath)) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'File not found'
        context_response -Response $Response -StatusCode 404 -String $jsonResponse -ContentType "application/json"
        return
    }

    $fileInfo = Get-Item $fullPath

    if ($fileInfo -is [System.IO.DirectoryInfo]) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Cannot preview a folder'
        context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Detect MIME type
    $extension = $fileInfo.Extension.ToLower()
    $mimeType = switch ($extension) {
        '.txt'  { 'text/plain' }
        '.html' { 'text/html' }
        '.css'  { 'text/css' }
        '.js'   { 'application/javascript' }
        '.json' { 'application/json' }
        '.xml'  { 'application/xml' }
        '.md'   { 'text/markdown' }
        '.ps1'  { 'text/plain' }
        '.psm1' { 'text/plain' }
        '.psd1' { 'text/plain' }
        '.yaml' { 'text/yaml' }
        '.yml'  { 'text/yaml' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.png'  { 'image/png' }
        '.gif'  { 'image/gif' }
        '.svg'  { 'image/svg+xml' }
        '.webp' { 'image/webp' }
        '.bmp'  { 'image/bmp' }
        '.pdf'  { 'application/pdf' }
        '.mp3'  { 'audio/mpeg' }
        '.wav'  { 'audio/wav' }
        '.ogg'  { 'audio/ogg' }
        '.mp4'  { 'video/mp4' }
        '.webm' { 'video/webm' }
        default { 'application/octet-stream' }
    }

    # Determine file category
    $category = 'unknown'
    if ($mimeType.StartsWith('text/') -or $mimeType -eq 'application/json' -or $mimeType -eq 'application/xml' -or $mimeType -eq 'application/javascript') {
        $category = 'text'
    } elseif ($mimeType.StartsWith('image/')) {
        $category = 'image'
    } elseif ($mimeType -eq 'application/pdf') {
        $category = 'pdf'
    } elseif ($mimeType.StartsWith('audio/')) {
        $category = 'audio'
    } elseif ($mimeType.StartsWith('video/')) {
        $category = 'video'
    }

    # Mode: metadata
    if ($mode -eq 'metadata') {
        $metadata = @{
            name = $fileInfo.Name
            path = $filePath
            size = $fileInfo.Length
            modified = $fileInfo.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
            extension = $extension
            mimeType = $mimeType
            category = $category
        }

        $jsonResponse = New-JsonResponse -status 'success' -message 'Metadata retrieved' -data $metadata
        context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Mode: content (serve file for preview)
    if ($mode -eq 'content') {
        # Limit text file size to 1MB for preview
        if ($category -eq 'text' -and $fileInfo.Length -gt 1MB) {
            $jsonResponse = New-JsonResponse -status 'fail' -message 'File too large for text preview (max 1MB)'
            context_response -Response $Response -StatusCode 413 -String $jsonResponse -ContentType "application/json"
            return
        }

        # Serve the file
        context_response -Response $Response -StatusCode 200 -Path $fullPath -ContentType $mimeType
        return
    }

    # Default: return file info
    $info = @{
        name = $fileInfo.Name
        size = $fileInfo.Length
        modified = $fileInfo.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
        mimeType = $mimeType
        category = $category
    }

    $jsonResponse = New-JsonResponse -status 'success' -message 'File info retrieved' -data $info
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error in preview GET: $($_.Exception.Message)" -Data @{ UserID = $userID; Path = $filePath }

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
