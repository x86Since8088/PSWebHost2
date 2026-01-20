param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Dot-source File Explorer helper functions
try {
    $helperPath = Join-Path $PSScriptRoot "..\..\..\..\..\modules\FileExplorerHelper.ps1"

    if (-not (Test-Path $helperPath)) {
        throw "Helper file not found: $helperPath"
    }

    # Always dot-source (each script scope needs its own copy)
    . $helperPath
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to load FileExplorerHelper.ps1: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Validate session
$userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
if (-not $userID) { return }

# Get query parameters
$queryParams = Get-WebHostFileExplorerQueryParams -Request $Request
$logicalPath = $queryParams['path']

if (-not $logicalPath) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing path parameter'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Resolve logical path to physical path with authorization
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'read'
    if (-not $pathResult) { return }

    $fullPath = $pathResult.PhysicalPath

    if (-not (Test-Path $fullPath)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'File not found'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    $fileInfo = Get-Item $fullPath

    if ($fileInfo -is [System.IO.DirectoryInfo]) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Cannot download a folder (use batch download)'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Get file size and MIME type
    $fileSize = $fileInfo.Length
    $mimeType = Get-WebHostFileExplorerMimeType -Extension $fileInfo.Extension

    # Parse Range header
    $rangeHeader = $Request.Headers["Range"]

    if ($rangeHeader) {
        Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Range request: $rangeHeader" -Data @{ UserID = $userID; Path = $logicalPath }

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
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error in download GET: $($_.Exception.Message)" -Data @{ UserID = $userID; Path = $logicalPath }

    # Response might already be closed
    try {
        $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
        context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
    }
    catch {
        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Could not send error response (response already closed)" -Data @{ Error = $_.Exception.Message }
    }
}
