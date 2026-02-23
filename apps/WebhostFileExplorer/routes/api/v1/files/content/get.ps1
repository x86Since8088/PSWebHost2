param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Get file content for editing

.DESCRIPTION
    GET /api/v1/files/content?path=<path>
    Returns file content, size, encoding, and last modified date

.EXAMPLE
    GET /api/v1/files/content?path=System:C/test.txt
    Returns: { status: 'success', data: { content, size, encoding, lastModified } }
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

# Parse query parameters
$queryParams = @{}
if ($Request.Url.Query) {
    $Request.Url.Query.TrimStart('?').Split('&') | ForEach-Object {
        $parts = $_.Split('=')
        if ($parts.Length -eq 2) {
            $queryParams[$parts[0]] = [System.Web.HttpUtility]::UrlDecode($parts[1])
        }
    }
}

$logicalPath = $queryParams['path']

if (-not $logicalPath) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: path'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Resolve path with read permission
    $roles = $sessiondata.Roles
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $roles -Response $Response -RequiredPermission 'read'
    if (-not $pathResult) { return }

    $physicalPath = $pathResult.PhysicalPath

    # Check if file exists
    if (-not (Test-Path $physicalPath -PathType Leaf)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'File not found'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    # Get file info
    $fileInfo = Get-Item $physicalPath

    # Read file content with UTF-8 encoding (default)
    try {
        $content = Get-Content -Path $physicalPath -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # If UTF-8 fails, try default encoding
        try {
            $content = Get-Content -Path $physicalPath -Raw -ErrorAction Stop
        }
        catch {
            throw "Failed to read file: $($_.Exception.Message)"
        }
    }

    # Detect encoding (simple detection)
    $encoding = 'utf-8'
    if ($content -match '[^\x00-\x7F]') {
        # Contains non-ASCII characters, likely UTF-8
        $encoding = 'utf-8'
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Loaded file content: $physicalPath ($($fileInfo.Length) bytes)" -Data @{
        UserID = $userID
        Path = $logicalPath
        Size = $fileInfo.Length
    }

    $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'File loaded' -Data @{
        content = $content
        size = $fileInfo.Length
        encoding = $encoding
        lastModified = $fileInfo.LastWriteTime.ToString('o')
    }

    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{
        UserID = $userID
        Path = $logicalPath
    }
}
