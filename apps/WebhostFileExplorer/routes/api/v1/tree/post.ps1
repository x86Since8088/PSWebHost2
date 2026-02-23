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
    Expand tree node to get its child folders

.EXAMPLE
    # Expand personal storage root
    .\post.ps1 -Test -Query @{ expandPath = 'local|localhost|User:me' }

.EXAMPLE
    # Expand subfolder
    .\post.ps1 -Test -Query @{ expandPath = 'local|localhost|User:me/Documents' }

.EXAMPLE
    # Expand site folder (requires site_admin role)
    .\post.ps1 -Test -Roles @('authenticated','site_admin') -Query @{ expandPath = 'local|localhost|Site:public' }
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
    Write-Host "`n=== Tree POST Test Mode ===" -ForegroundColor Cyan
    Write-Host "UserID: $($sessiondata.UserID)" -ForegroundColor Yellow
    Write-Host "Roles: $($Roles -join ', ')" -ForegroundColor Yellow

    if ($Query.Count -eq 0) {
        Write-Host "`n=== Usage Examples ===" -ForegroundColor Yellow
        Write-Host ".\post.ps1 -Test -Query @{ expandPath = 'local|localhost|User:me' }" -ForegroundColor Gray
        Write-Host ".\post.ps1 -Test -Query @{ expandPath = 'local|localhost|User:me/Documents' }" -ForegroundColor Gray
        Write-Host ".\post.ps1 -Test -Roles @('authenticated','site_admin') -Query @{ expandPath = 'local|localhost|Site:public' }" -ForegroundColor Gray
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

# Read request body
if ($Test) {
    # In test mode, create mock request body
    $data = @{
        treeState = @{ nodes = @() }
        expandPath = if ($Query['expandPath']) { $Query['expandPath'] } else { 'local|localhost|User:me' }
    } | ConvertTo-Json | ConvertFrom-Json
} else {
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
}

# Validate required parameters
if (-not $data.expandPath) {
    $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'Missing required parameter: expandPath'
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 400 -JsonContent $json
    return
}

$expandPath = $data.expandPath

if ($Test) {
    Write-Host "Expand Path: $expandPath" -ForegroundColor Yellow
}

try {
    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        $Global:PSWebServer['WebhostFileExplorer'].Stats.TreeRequests++
        $Global:PSWebServer['WebhostFileExplorer'].Stats.LastTreeRequest = Get-Date
    }

    # Parse path format: local|localhost|user:me/Documents
    if ($expandPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
        $node = $matches[1]        # "local"
        $nodeName = $matches[2]    # "localhost"
        $logicalPath = $matches[3] # "user:me/Documents"

        if ($Test) {
            Write-Host "Parsed Path Components:" -ForegroundColor Cyan
            Write-Host "  Node: $node" -ForegroundColor Yellow
            Write-Host "  NodeName: $nodeName" -ForegroundColor Yellow
            Write-Host "  Logical Path: $logicalPath" -ForegroundColor Yellow
        }
    }
    else {
        # Fallback: treat entire path as logical path
        $node = "local"
        $nodeName = "localhost"
        $logicalPath = $expandPath

        if ($Test) {
            Write-Host "Using fallback parsing for path: $expandPath" -ForegroundColor Yellow
        }
    }

    # Special handling for User:others root expansion (list all users)
    if ($logicalPath -eq 'User:others') {
        # Require system_admin role
        if ($sessiondata.Roles -notcontains 'system_admin') {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'system_admin role required for User:others access'
            if ($Test) {
                Write-Host "`n=== Test Result: 403 Forbidden ===" -ForegroundColor Red
                Write-Host "Message: system_admin role required" -ForegroundColor Yellow
                return
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 403 -JsonContent $json
            return
        }

        # Get database path
        $dbPath = if ($Global:PSWebServer['Config'].Database.Path) {
            $Global:PSWebServer['Config'].Database.Path
        } else {
            $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
                $Global:PSWebServer.Project_Root.Path
            } else {
                Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            }
            Join-Path $projectRoot "system\db\sqlite\PSWebHost.db"
        }

        if (-not (Test-Path $dbPath)) {
            $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'User database not found'
            if ($Test) {
                Write-Host "`n=== Test Result: 500 Internal Server Error ===" -ForegroundColor Red
                Write-Host "Message: User database not found: $dbPath" -ForegroundColor Yellow
                return
            }
            Send-WebHostFileExplorerResponse -Response $Response -StatusCode 500 -JsonContent $json
            return
        }

        # Query all users
        $query = "SELECT UserID, Email, FirstName, LastName FROM Users ORDER BY Email;"
        $users = Invoke-PSWebSQLiteQuery -File $dbPath -Query $query

        if ($Test) {
            Write-Host "Found $($users.Count) users in database" -ForegroundColor Green
        }

        # Build children list with email/last4 format
        $children = @()
        foreach ($user in $users) {
            $last4 = $user.UserID.Substring([Math]::Max(0, $user.UserID.Length - 4))
            $displayName = if ($user.FirstName -or $user.LastName) {
                "$($user.Email) - $($user.FirstName) $($user.LastName) (...$last4)"
            } else {
                "$($user.Email) (...$last4)"
            }

            # Child path: local|localhost|User:others/{email}/{last4}
            $childPath = "$node|$nodeName|User:others/$($user.Email)/$last4"

            $children += @{
                path = $childPath
                name = $displayName
                type = "folder"
                hasContent = $true
                isExpanded = $false
                children = @()
                metadata = @{
                    userID = $user.UserID
                    email = $user.Email
                }
            }
        }

        # Build expanded node
        $expandedNode = @{
            path = $expandPath
            name = "User Files (Admin)"
            type = "folder"
            hasContent = $children.Count -gt 0
            isExpanded = $true
            children = $children
        }

        # Return response
        $responseData = @{
            status = "success"
            message = "User listing retrieved successfully"
            expandedNode = $expandedNode
            path = $expandPath
            childCount = $children.Count
        }

        if ($Test) {
            Write-Host "`n=== Tree POST Test Results (User:others) ===" -ForegroundColor Cyan
            Write-Host "Status: 200 OK" -ForegroundColor Green
            Write-Host "User Count: $($children.Count)" -ForegroundColor Yellow
            Write-Host "`nUsers:" -ForegroundColor Cyan
            foreach ($child in $children) {
                Write-Host "  - $($child.name)" -ForegroundColor Gray
            }
            Write-Host "`n=== End Test Results ===" -ForegroundColor Cyan
            return
        }

        $jsonResponse = $responseData | ConvertTo-Json -Depth 10 -Compress
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $jsonResponse
        return
    }

    # Resolve logical path to physical path with authorization
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $logicalPath -UserID $userID -Roles $sessiondata.Roles -Response $Response -RequiredPermission 'read'
    if (-not $pathResult) { return }

    # Get the physical folder
    $physicalPath = $pathResult.PhysicalPath

    if ($Test) {
        Write-Host "Physical Path: $physicalPath" -ForegroundColor Yellow
    }

    # Create folder if it doesn't exist (for personal/bucket storage)
    if ($pathResult.StorageType -in @('personal', 'bucket') -and -not (Test-Path $physicalPath)) {
        New-Item -Path $physicalPath -ItemType Directory -Force | Out-Null
        if ($Test) {
            Write-Host "Created folder: $physicalPath" -ForegroundColor Green
        }
    }

    # Validate path exists
    if (-not (Test-Path $physicalPath)) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message "Path does not exist: $expandPath"
        if ($Test) {
            Write-Host "`n=== Test Result: 404 Not Found ===" -ForegroundColor Red
            Write-Host "Message: Path does not exist: $expandPath" -ForegroundColor Yellow
            Write-Host "Physical Path: $physicalPath" -ForegroundColor Yellow
            return
        }
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 404 -JsonContent $json
        return
    }

    $folderInfo = Get-Item $physicalPath
    if ($folderInfo -isnot [System.IO.DirectoryInfo]) {
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

    # Get immediate children (not recursive)
    $children = Get-ChildItem $physicalPath -ErrorAction SilentlyContinue | ForEach-Object {
        $hasContent = $false
        $itemType = "file"

        if ($_.PSIsContainer) {
            $itemType = "folder"
            # Check if folder has any content (HasContent check)
            $firstChild = Get-ChildItem $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 1
            $hasContent = $null -ne $firstChild
        }

        # Build child path in format: node|nodename|logicalpath
        $childLogicalPath = if ($logicalPath -eq '') {
            $_.Name
        } else {
            "$logicalPath/$($_.Name)"
        }
        $childPath = "$node|$nodeName|$childLogicalPath"

        @{
            path = $childPath
            name = $_.Name
            type = $itemType
            lastWriteTime = $_.LastWriteTime.ToString("o")
            hasContent = $hasContent
            isExpanded = $false
            children = @()
        }
    }

    # Build expanded node structure
    $expandedNode = @{
        path = $expandPath
        name = Split-Path $logicalPath -Leaf
        type = "folder"
        lastWriteTime = $folderInfo.LastWriteTime.ToString("o")
        hasContent = $children.Count -gt 0
        isExpanded = $true
        children = $children
    }

    # Return response with expanded node
    $responseData = @{
        status = "success"
        message = "Tree expanded successfully"
        expandedNode = $expandedNode
        path = $expandPath
        childCount = $children.Count
    }

    # Test mode output
    if ($Test) {
        Write-Host "`n=== Tree POST Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        Write-Host "Content-Type: application/json" -ForegroundColor Gray
        Write-Host "`nExpanded Node:" -ForegroundColor Cyan
        $expandedNode | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "Path: $expandPath" -ForegroundColor Yellow
        Write-Host "Physical Path: $physicalPath" -ForegroundColor Yellow
        Write-Host "Child Count: $($children.Count)" -ForegroundColor Yellow
        Write-Host "Storage Type: $($pathResult.StorageType)" -ForegroundColor Yellow
        Write-Host "`n=== End Test Results ===" -ForegroundColor Cyan
        return
    }

    $jsonResponse = $responseData | ConvertTo-Json -Depth 10 -Compress
    Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $jsonResponse
}
catch {
    if ($Test) {
        Write-Host "`n=== Tree POST Test Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host "`n=== End Test Error ===" -ForegroundColor Red
        return
    }
    Send-WebHostFileExplorerError -ErrorRecord $_ -Context $Context -Request $Request -Response $Response -SessionData $sessiondata -LogData @{ UserID = $userID; Path = $expandPath }
}
