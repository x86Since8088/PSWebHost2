param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; message = $message } | ConvertTo-Json
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
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Cannot download a folder (use batch download)'
        context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Get file size
    $fileSize = $fileInfo.Length

    # Detect MIME type
    $extension = $fileInfo.Extension.ToLower()
    $mimeType = switch ($extension) {
        '.txt'  { 'text/plain' }
        '.html' { 'text/html' }
        '.css'  { 'text/css' }
        '.js'   { 'application/javascript' }
        '.json' { 'application/json' }
        '.xml'  { 'application/xml' }
        '.pdf'  { 'application/pdf' }
        '.zip'  { 'application/zip' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.png'  { 'image/png' }
        '.gif'  { 'image/gif' }
        '.svg'  { 'image/svg+xml' }
        '.mp3'  { 'audio/mpeg' }
        '.mp4'  { 'video/mp4' }
        default { 'application/octet-stream' }
    }

    # Parse Range header
    $rangeHeader = $Request.Headers["Range"]

    if ($rangeHeader) {
        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Range request: $rangeHeader" -Data @{ UserID = $userID; Path = $filePath }

        if ($rangeHeader -match 'bytes=(\d+)-(\d*)') {
            $start = [int64]$matches[1]
            $end = if ($matches[2]) { [int64]$matches[2] } else { $fileSize - 1 }

            # Validate range
            if ($start -ge $fileSize -or $start -lt 0 -or ($end -ne ($fileSize - 1) -and $end -ge $fileSize)) {
                $Response.StatusCode = 416 # Range Not Satisfiable
                $Response.AddHeader("Content-Range", "bytes */$fileSize")
                $Response.Close()
                return
            }

            # Calculate content length
            $contentLength = $end - $start + 1

            # Log download request
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Serving partial file download: $($fileInfo.Name)" -Data @{
                UserID = $userID
                File = $fileInfo.Name
                Size = $fileSize
                Range = "$start-$end"
                ContentLength = $contentLength
            }

            # Set response headers for partial content
            $Response.StatusCode = 206 # Partial Content
            $Response.ContentType = $mimeType
            $Response.ContentLength64 = $contentLength
            $Response.AddHeader("Accept-Ranges", "bytes")
            $Response.AddHeader("Content-Range", "bytes $start-$end/$fileSize")
            $Response.AddHeader("Content-Disposition", "attachment; filename=`"$($fileInfo.Name)`"")

            # Stream file chunk
            $stream = [System.IO.File]::OpenRead($fullPath)
            try {
                $stream.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null

                # Buffer size for streaming (64KB chunks)
                $bufferSize = 64KB
                $buffer = New-Object byte[] $bufferSize
                $remaining = $contentLength

                while ($remaining -gt 0) {
                    $toRead = [Math]::Min($bufferSize, $remaining)
                    $bytesRead = $stream.Read($buffer, 0, $toRead)

                    if ($bytesRead -eq 0) { break }

                    $Response.OutputStream.Write($buffer, 0, $bytesRead)
                    $remaining -= $bytesRead
                }
            }
            finally {
                $stream.Close()
                $Response.Close()
            }

            return
        }
    }

    # No range request - serve full file
    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Serving full file download: $($fileInfo.Name)" -Data @{
        UserID = $userID
        File = $fileInfo.Name
        Size = $fileSize
    }

    $Response.StatusCode = 200
    $Response.ContentType = $mimeType
    $Response.ContentLength64 = $fileSize
    $Response.AddHeader("Accept-Ranges", "bytes")
    $Response.AddHeader("Content-Disposition", "attachment; filename=`"$($fileInfo.Name)`"")

    # Stream full file
    $stream = [System.IO.File]::OpenRead($fullPath)
    try {
        $bufferSize = 64KB
        $buffer = New-Object byte[] $bufferSize

        while ($true) {
            $bytesRead = $stream.Read($buffer, 0, $bufferSize)
            if ($bytesRead -eq 0) { break }
            $Response.OutputStream.Write($buffer, 0, $bytesRead)
        }
    }
    finally {
        $stream.Close()
        $Response.Close()
    }
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error in download GET: $($_.Exception.Message)" -Data @{ UserID = $userID; Path = $filePath }

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    # Response might already be closed
    try {
        context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
    }
    catch {
        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Could not send error response (response already closed)" -Data @{ Error = $_.Exception.Message }
    }
}
