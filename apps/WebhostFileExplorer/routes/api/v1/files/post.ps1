param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Dot-source File Explorer helper functions
try {
    $helperPath = Join-Path $PSScriptRoot "..\..\..\..\modules\FileExplorerHelper.ps1"

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

# Validate action
if (-not $data.action) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: action'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

try {
    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        $Global:PSWebServer['WebhostFileExplorer'].Stats.FileOperations++
        $Global:PSWebServer['WebhostFileExplorer'].Stats.LastOperation = Get-Date
    }

    switch ($data.action) {
        'createFolder' {
            # Create a new folder
            if (-not $data.name) {
                throw "Missing required parameter: name"
            }

            # Get logical path (default to User:me if not specified)
            $logicalPath = if ($data.path) { $data.path } else { "User:me" }

            # Resolve path with write permission
            $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
            if (-not $pathResult) { return }

            # Create folder at physical path
            $targetPath = Join-Path $pathResult.PhysicalPath $data.name
            New-Item -Path $targetPath -ItemType Directory -Force | Out-Null

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Folder created successfully' -Data @{
                path = "$logicalPath/$($data.name)"
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        'uploadFile' {
            # Upload/save a file
            if (-not $data.name -or -not $data.content) {
                throw "Missing required parameters: name, content"
            }

            # Get logical path (default to User:me if not specified)
            $logicalPath = if ($data.path) { $data.path } else { "User:me" }

            # Resolve path with write permission
            $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
            if (-not $pathResult) { return }

            # Create target folder if it doesn't exist
            if (-not (Test-Path $pathResult.PhysicalPath)) {
                New-Item -Path $pathResult.PhysicalPath -ItemType Directory -Force | Out-Null
            }

            $targetPath = Join-Path $pathResult.PhysicalPath $data.name

            # Decode base64 content if present
            if ($data.encoding -eq 'base64') {
                $bytes = [System.Convert]::FromBase64String($data.content)
                [System.IO.File]::WriteAllBytes($targetPath, $bytes)
            }
            else {
                Set-Content -Path $targetPath -Value $data.content -Force
            }

            $result = Get-Item $targetPath

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'File uploaded successfully' -Data @{
                file = $result.Name
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        'rename' {
            # Rename a file or folder
            if (-not $data.oldName -or -not $data.newName) {
                throw "Missing required parameters: oldName, newName"
            }

            # Get logical path (default to User:me if not specified)
            $logicalPath = if ($data.path) { $data.path } else { "User:me" }

            # Resolve path with write permission
            $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
            if (-not $pathResult) { return }

            # Build old and new paths
            $oldPath = Join-Path $pathResult.PhysicalPath $data.oldName
            $newPath = Join-Path $pathResult.PhysicalPath $data.newName

            # Rename the item
            Rename-Item -Path $oldPath -NewName $data.newName -Force
            $result = Get-Item $newPath

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Item renamed successfully' -Data @{
                newName = $result.Name
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        'delete' {
            # Delete a file or folder
            if (-not $data.name) {
                throw "Missing required parameter: name"
            }

            # Get logical path (default to User:me if not specified)
            $logicalPath = if ($data.path) { $data.path } else { "User:me" }

            # Resolve path with write permission (delete requires write)
            $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'write'
            if (-not $pathResult) { return }

            # Build target path
            $targetPath = Join-Path $pathResult.PhysicalPath $data.name

            # Delete the item
            if ($data.isFolder) {
                Remove-Item -Path $targetPath -Recurse -Force
            } else {
                Remove-Item -Path $targetPath -Force
            }

            $json = New-WebHostFileExplorerResponse -Status 'success' -Message 'Item deleted successfully' -Data @{
                removed = $true
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
        }

        default {
            throw "Unknown action: $($data.action)"
        }
    }
}
catch {
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{ UserID = $userID; Action = $data.action }
}
