param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @()
)

<#
.SYNOPSIS
    Returns all available root paths for the current user

.DESCRIPTION
    Consolidates User:me, Bucket:*, Site:*, and System:* paths into a single response
    based on the user's roles and permissions.

.EXAMPLE
    # Get roots for regular user
    .\get.ps1 -Test

.EXAMPLE
    # Get roots for site admin
    .\get.ps1 -Test -Roles @('authenticated','site_admin')

.EXAMPLE
    # Get roots for system admin
    .\get.ps1 -Test -Roles @('authenticated','system_admin')
#>

# Import File Explorer helper module functions
try {Import-TrackedModule "FileExplorerHelper"
}
catch {
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
    Write-Host "`n=== Roots GET Test Mode ===" -ForegroundColor Cyan
    Write-Host "UserID: $($sessiondata.UserID)" -ForegroundColor Yellow
    Write-Host "Roles: $($Roles -join ', ')" -ForegroundColor Yellow
}

# Validate session
if ($Test) {
    $userID = $sessiondata.UserID
} else {
    $userID = Test-WebHostFileExplorerSession -SessionData $sessiondata -Response $Response
    if (-not $userID) { return }
}

try {
    $roots = @()

    # 1. Always include User:me (personal storage)
    $roots += @{
        path = "local|localhost|User:me"
        name = "My Files"
        type = "personal"
        isExpanded = $false
        hasContent = $true
        children = @()
    }

    # 2. Get user's buckets
    $getBucketsScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Bucket_Get.ps1"
    if (Test-Path $getBucketsScript) {
        try {
            $buckets = & $getBucketsScript -UserID $userID
            foreach ($bucket in $buckets) {
                $roots += @{
                    path = "local|localhost|Bucket:$($bucket.BucketID)"
                    name = $bucket.Name
                    type = "bucket"
                    description = $bucket.Description
                    accessLevel = $bucket.AccessLevel
                    isExpanded = $false
                    hasContent = $true
                    children = @()
                }
            }
        }
        catch {
            Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to load buckets for roots: $($_.Exception.Message)"
        }
    }

    # 3. Site admin paths
    if ($sessiondata.Roles -contains 'site_admin') {
        $projectRoot = $Global:PSWebServer.Project_Root.Path

        $roots += @{
            path = "local|localhost|Site:public"
            name = "Site: Public"
            type = "site"
            description = "Public web assets"
            isExpanded = $false
            hasContent = $true
            children = @()
        }

        $roots += @{
            path = "local|localhost|Site:routes"
            name = "Site: Routes"
            type = "site"
            description = "API routes"
            isExpanded = $false
            hasContent = $true
            children = @()
        }

        $roots += @{
            path = "local|localhost|Site:apps"
            name = "Site: Apps"
            type = "site"
            description = "Application folders"
            isExpanded = $false
            hasContent = $true
            children = @()
        }
    }

    # 4. System admin paths (Windows drives or Unix mounts)
    if ($sessiondata.Roles -contains 'system_admin') {
        if ($IsWindows -or $env:OS -like "Windows*") {
            # Windows: Add drive letters
            $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
            foreach ($drive in $drives) {
                $roots += @{
                    path = "local|localhost|System:$($drive.Name)"
                    name = "System: $($drive.Name):"
                    type = "system"
                    description = $drive.Description
                    isExpanded = $false
                    hasContent = $true
                    children = @()
                }
            }
        }
        else {
            # Unix: Add root
            $roots += @{
                path = "local|localhost|System:root"
                name = "System: Root"
                type = "system"
                description = "Root filesystem"
                isExpanded = $false
                hasContent = $true
                children = @()
            }
        }
    }

    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        if (-not $Global:PSWebServer['WebhostFileExplorer'].Stats.RootRequests) {
            $Global:PSWebServer['WebhostFileExplorer'].Stats.RootRequests = 0
        }
        $Global:PSWebServer['WebhostFileExplorer'].Stats.RootRequests++
    }

    $responseData = @{
        status = 'success'
        message = "Retrieved $($roots.Count) root paths"
        roots = $roots
        userID = $userID
        roles = $sessiondata.Roles
    }

    $json = $responseData | ConvertTo-Json -Depth 10 -Compress

    if ($Test) {
        Write-Host "`n=== Response: 200 OK ===" -ForegroundColor Green
        $responseData | ConvertTo-Json -Depth 10 | Write-Host
    } else {
        context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
    }
}
catch {
    if ($Test) {
        Write-Host "`n=== Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    } else {
        Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error getting roots: $($_.Exception.Message)"
        $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
        context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
    }
}
