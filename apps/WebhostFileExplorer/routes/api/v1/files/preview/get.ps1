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
$mode = $queryParams['mode'] # 'content', 'metadata', or 'thumbnail'

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
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Cannot preview a folder'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Detect MIME type and category
    $mimeType = Get-WebHostFileExplorerMimeType -Extension $fileInfo.Extension
    $category = Get-WebHostFileExplorerCategory -MimeType $mimeType

    # Mode: metadata
    if ($mode -eq 'metadata') {
        $metadata = @{
            name = $fileInfo.Name
            path = $logicalPath
            size = $fileInfo.Length
            modified = $fileInfo.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
            extension = $fileInfo.Extension.ToLower()
            mimeType = $mimeType
            category = $category
        }

        $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Metadata retrieved' -Data $metadata
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        return
    }

    # Mode: content (serve file for preview)
    if ($mode -eq 'content') {
        # Limit text file size to 1MB for preview
        if ($category -eq 'text' -and $fileInfo.Length -gt 1MB) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'File too large for text preview (max 1MB)'
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 413 -JsonContent $json
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

    $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'File info retrieved' -Data $info
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{ UserID = $userID; Path = $logicalPath }
}
