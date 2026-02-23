param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{}
)

<#
.SYNOPSIS
    Get folder contents (list files and subfolders)

.EXAMPLE
    # List personal storage root
    .\get.ps1 -Test -Query @{ path = 'User:me' }

.EXAMPLE
    # List subfolder
    .\get.ps1 -Test -Query @{ path = 'User:me/Documents' }

.EXAMPLE
    # List site public folder (requires site_admin role)
    .\get.ps1 -Test -Roles @('authenticated','site_admin') -Query @{ path = 'Site:public' }

.EXAMPLE
    # List bucket contents
    .\get.ps1 -Test -Query @{ path = 'Bucket:abc-123' }
#>

# Import File Explorer helper module functions
try {Import-TrackedModule "FileExplorerHelper"
}
catch {
    if ($Test) {
        Write-Host "`n=== File Explorer Helper Load Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host "`n=== End Error ===" -ForegroundColor Red
        return
    }
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to import FileExplorerHelper module: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode 500 -String $Report.body -ContentType $Report.contentType
    return
}

# Handle test mode
if ($Test) {
    # Create mock sessiondata
    if ($Roles.Count -eq 0) {
        $Roles = @('authenticated')
    }
    $sessiondata = @{
        Roles = $Roles
        UserID = 'test-user-123'
        SessionID = 'test-session'
    }
    Write-Host "`n=== Files GET Test Mode ===" -ForegroundColor Cyan
    Write-Host "UserID: $($sessiondata.UserID)" -ForegroundColor Yellow
    Write-Host "Roles: $($Roles -join ', ')" -ForegroundColor Yellow

    if ($Query.Count -eq 0) {
        Write-Host "`n=== Usage Examples ===" -ForegroundColor Yellow
        Write-Host ".\get.ps1 -Test -Query @{ path = 'User:me' }" -ForegroundColor Gray
        Write-Host ".\get.ps1 -Test -Query @{ path = 'User:me/Documents' }" -ForegroundColor Gray
        Write-Host ".\get.ps1 -Test -Roles @('authenticated','site_admin') -Query @{ path = 'Site:public' }" -ForegroundColor Gray
        Write-Host ".\get.ps1 -Test -Query @{ path = 'Bucket:abc-123' }" -ForegroundColor Gray
        return
    }
}

# Validate session
if ($Test) {
    $userID = $sessiondata.UserID
} else {
    $userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
    if (-not $userID) { return }
}

# Get logical path parameter (e.g., "User:me/Documents", "Bucket:abc-123", "Site/public", "System:C")
if ($Test -and $Query.Count -gt 0) {
    $logicalPath = $Query['path']
} else {
    $logicalPath = $Request.QueryString['path']
}
if (-not $logicalPath) { $logicalPath = 'User:me' }  # Default to personal storage

# Parse path format: local|localhost|User:me/Documents
# The frontend sends paths in this format after initial load
if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
    $node = $matches[1]        # "local"
    $nodeName = $matches[2]    # "localhost"
    $parsedLogicalPath = $matches[3]  # "User:me/Documents"

    if ($Test) {
        Write-Host "Parsed Path Components:" -ForegroundColor Cyan
        Write-Host "  Node: $node" -ForegroundColor Yellow
        Write-Host "  NodeName: $nodeName" -ForegroundColor Yellow
        Write-Host "  Original: $logicalPath" -ForegroundColor Yellow
        Write-Host "  Parsed Logical Path: $parsedLogicalPath" -ForegroundColor Yellow
    }

    # Use the parsed logical path
    $logicalPath = $parsedLogicalPath
}
elseif ($Test) {
    Write-Host "Logical Path: $logicalPath (no parsing needed)" -ForegroundColor Yellow
}

try {
    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        $Global:PSWebServer['WebhostFileExplorer'].Stats.TreeRequests++
        $Global:PSWebServer['WebhostFileExplorer'].Stats.LastTreeRequest = Get-Date
    }

    # Resolve logical path to physical path with authorization
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'read'
    if (-not $pathResult) { return }

    # Get the physical folder
    $physicalPath = $pathResult.PhysicalPath

    # Create folder if it doesn't exist (for personal/bucket storage)
    if ($pathResult.StorageType -in @('personal', 'bucket') -and -not (Test-Path $physicalPath)) {
        New-Item -Path $physicalPath -ItemType Directory -Force | Out-Null
    }

    # Validate path exists
    if (-not (Test-Path $physicalPath)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Path does not exist: $logicalPath"
        if ($Test) {
            Write-Host "`n=== Test Result: 404 Not Found ===" -ForegroundColor Red
            Write-Host "Message: Path does not exist: $logicalPath" -ForegroundColor Yellow
            Write-Host "Physical Path: $physicalPath" -ForegroundColor Yellow
            return
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    $userFolder = Get-Item $physicalPath
    if ($userFolder -isnot [System.IO.DirectoryInfo]) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Path is not a directory"
        if ($Test) {
            Write-Host "`n=== Test Result: 400 Bad Request ===" -ForegroundColor Red
            Write-Host "Message: Path is not a directory" -ForegroundColor Yellow
            Write-Host "Physical Path: $physicalPath" -ForegroundColor Yellow
            return
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
        return
    }

    # Get immediate children only (not recursive) - flat list for center pane
    $children = Get-ChildItem $physicalPath -ErrorAction SilentlyContinue | ForEach-Object {
        $itemType = if ($_.PSIsContainer) { "folder" } else { "file" }

        # Build child path in format: local|localhost|logicalpath
        $childLogicalPath = if ($logicalPath -eq 'User:me') {
            "User:me/$($_.Name)"
        } else {
            "$logicalPath/$($_.Name)"
        }
        $childPath = "local|localhost|$childLogicalPath"

        @{
            path = $childPath
            name = $_.Name
            type = $itemType
            size = if ($itemType -eq "file") { $_.Length } else { $null }
            modified = $_.LastWriteTime.ToString("o")
            created = $_.CreationTime.ToString("o")
            extension = if ($itemType -eq "file") { $_.Extension.ToLower() } else { $null }
        }
    }

    # Add metadata to response
    $responseData = @{
        folderPath = "local|localhost|$logicalPath"
        children = $children
        storageType = $pathResult.StorageType
        accessLevel = $pathResult.AccessLevel
        basePath = $pathResult.BasePath
        childCount = $children.Count
    }

    # Return JSON
    $jsonResponse = $responseData | ConvertTo-Json -Depth 10 -Compress

    # Test mode output
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        Write-Host "Content-Type: application/json" -ForegroundColor Gray
        Write-Host "`nResponse Data:" -ForegroundColor Cyan
        $responseData | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "Path: $logicalPath" -ForegroundColor Yellow
        Write-Host "Physical Path: $physicalPath" -ForegroundColor Yellow
        Write-Host "Storage Type: $($pathResult.StorageType)" -ForegroundColor Yellow
        Write-Host "Access Level: $($pathResult.AccessLevel)" -ForegroundColor Yellow
        Write-Host "File Count: $($children.Count)" -ForegroundColor Yellow
        Write-Host "`n=== End Test Results ===" -ForegroundColor Cyan
        return
    }

    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $jsonResponse
}
catch {
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host "`n=== End Test Error ===" -ForegroundColor Red
        return
    }
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{ UserID = $userID; Path = $logicalPath }
}
