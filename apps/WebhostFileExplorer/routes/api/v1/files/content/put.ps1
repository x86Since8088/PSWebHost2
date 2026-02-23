param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Save file content

.DESCRIPTION
    PUT /api/v1/files/content
    Body: { path, content, encoding }
    Creates .bak backup before saving

.EXAMPLE
    PUT /api/v1/files/content
    Body: { "path": "System:C/test.txt", "content": "Hello World", "encoding": "utf-8" }
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

# Validate required fields
if (-not $data.path -or -not $data.PSObject.Properties['content']) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameters: path, content'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

$logicalPath = $data.path
$content = $data.content
$encoding = if ($data.encoding) { $data.encoding } else { 'utf-8' }

try {
    # Resolve path with write permission
    $roles = $sessiondata.Roles
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $roles -Response $Response -RequiredPermission 'write'
    if (-not $pathResult) { return }

    $physicalPath = $pathResult.PhysicalPath

    # Create backup if file exists
    if (Test-Path $physicalPath -PathType Leaf) {
        $backupPath = "$physicalPath.bak"
        Copy-Item -Path $physicalPath -Destination $backupPath -Force
        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Created backup: $backupPath" -Data @{
            UserID = $userID
            Path = $logicalPath
        }
    }

    # Save file content
    $encodingObj = switch ($encoding.ToLower()) {
        'utf-8' { [System.Text.Encoding]::UTF8 }
        'ascii' { [System.Text.Encoding]::ASCII }
        'unicode' { [System.Text.Encoding]::Unicode }
        default { [System.Text.Encoding]::UTF8 }
    }

    [System.IO.File]::WriteAllText($physicalPath, $content, $encodingObj)

    $fileInfo = Get-Item $physicalPath

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Saved file content: $physicalPath ($($fileInfo.Length) bytes)" -Data @{
        UserID = $userID
        Path = $logicalPath
        Size = $fileInfo.Length
        Encoding = $encoding
    }

    $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'File saved successfully' -Data @{
        size = $fileInfo.Length
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
