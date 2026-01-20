param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message, $data = $null) {
    $response = @{ status = $status; message = $message }
    if ($data) { $response.data = $data }
    return $response | ConvertTo-Json -Compress -Depth 10
}

# Get user ID from session
if (-not $sessiondata -or -not $sessiondata.UserID) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'User not authenticated'
    context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

# Check if user has admin role
$isSystemAdmin = $sessiondata.Roles -contains 'system_admin'
$isSiteAdmin = $sessiondata.Roles -contains 'site_admin'

if (-not $isSystemAdmin -and -not $isSiteAdmin) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Insufficient permissions. Requires system_admin or site_admin role.'
    context_response -Response $Response -StatusCode 403 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    $paths = @()

    if ($isSystemAdmin) {
        # System admin: Get all drives/mount points with logical path prefixes
        if ($IsWindows -or $env:OS -like "Windows*") {
            # Windows: Get all drive letters
            $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
            foreach ($drive in $drives) {
                $paths += @{
                    logicalPath = "System:$($drive.Name)"  # Logical path: System:C, System:D, etc.
                    path = $drive.Root                      # Physical path: C:\, D:\, etc.
                    display = "$($drive.Name): ($($drive.Description))"
                    type = "drive"
                    writable = $true
                }
            }
        }
        else {
            # Linux/Unix: Get mount points
            $paths += @{
                logicalPath = "System:root"               # Logical path: System:root
                path = "/"                                 # Physical path: /
                display = "Root (/)"
                type = "mount"
                writable = $true
            }

            # Try to read /proc/mounts for additional mount points
            if (Test-Path "/proc/mounts") {
                $mounts = Get-Content /proc/mounts | Where-Object { $_ -match '^/dev' } | ForEach-Object {
                    ($_ -split '\s+')[1]
                } | Where-Object { $_ -ne '/' } | Sort-Object -Unique

                foreach ($mount in $mounts) {
                    # Convert /mnt/data to mnt-data for logical path
                    $logicalName = $mount.TrimStart('/') -replace '/', '-'
                    $paths += @{
                        logicalPath = "System:$logicalName"  # Logical path: System:mnt-data
                        path = $mount                         # Physical path: /mnt/data
                        display = "Mount ($mount)"
                        type = "mount"
                        writable = $true
                    }
                }
            }
        }
    }
    elseif ($isSiteAdmin) {
        # Site admin: Site paths with logical path prefix
        $projectRoot = $Global:PSWebServer.Project_Root.Path

        $paths += @{
            logicalPath = "Site/public"                   # Logical path: Site/public
            path = Join-Path $projectRoot "public"        # Physical path
            display = "Public Web Assets (public/)"
            type = "directory"
            writable = $true
        }

        $paths += @{
            logicalPath = "Site/routes"                   # Logical path: Site/routes
            path = Join-Path $projectRoot "routes"        # Physical path
            display = "API Routes (routes/)"
            type = "directory"
            writable = $true
        }
    }

    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        if (-not $Global:PSWebServer['WebhostFileExplorer'].Stats.SystemPathRequests) {
            $Global:PSWebServer['WebhostFileExplorer'].Stats.SystemPathRequests = 0
        }
        $Global:PSWebServer['WebhostFileExplorer'].Stats.SystemPathRequests++
    }

    $jsonResponse = New-JsonResponse -status 'success' -message "Retrieved $($paths.Count) system paths" -data @{
        paths = $paths
        role = if ($isSystemAdmin) { "system_admin" } else { "site_admin" }
    }
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SystemPaths' -Message "Error getting system paths: $($_.Exception.Message)" -Data @{ UserID = $sessiondata.UserID }

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
