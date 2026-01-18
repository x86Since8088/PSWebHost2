param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Get user ID from session
if (-not $sessiondata -or -not $sessiondata.UserID) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'User not authenticated'
    context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

$userID = $sessiondata.UserID

# Get user's file-explorer folder
$getUserDataScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\UserData_Folder_Get.ps1"
if (-not (Test-Path $getUserDataScript)) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'UserData_Folder_Get.ps1 not found'
    context_response -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Update stats
    if ($Global:PSWebServer['WebhostFileExplorer']) {
        $Global:PSWebServer['WebhostFileExplorer'].Stats.TreeRequests++
        $Global:PSWebServer['WebhostFileExplorer'].Stats.LastTreeRequest = Get-Date
    }

    # Get or create the file-explorer folder for this user
    $userFolder = & $getUserDataScript -UserID $userID -Application "file-explorer" -CreateIfMissing

    if (-not $userFolder) {
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Failed to get user data folder'
        context_response -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Build file tree recursively
    function Get-FileTree {
        param (
            [System.IO.DirectoryInfo]$Directory
        )

        $result = @{
            name = $Directory.Name
            type = "folder"
            children = @()
        }

        try {
            # Get subdirectories
            $subDirs = Get-ChildItem -Path $Directory.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $subDirs) {
                $result.children += Get-FileTree -Directory $dir
            }

            # Get files
            $files = Get-ChildItem -Path $Directory.FullName -File -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $result.children += @{
                    name = $file.Name
                    type = "file"
                    size = $file.Length
                    modified = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                }
            }
        }
        catch {
            Write-Warning "Error reading directory $($Directory.FullName): $($_.Exception.Message)"
        }

        return $result
    }

    # Generate file tree
    $fileTree = Get-FileTree -Directory $userFolder

    # Return JSON
    $jsonResponse = $fileTree | ConvertTo-Json -Depth 10 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error in file-explorer GET: $($_.Exception.Message)" -Data @{ UserID = $userID }

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
