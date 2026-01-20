<#
.SYNOPSIS
    File Explorer Helper Module

.DESCRIPTION
    Provides reusable functions for File Explorer API endpoints including:
    - Path resolution with authorization
    - JSON response helpers
    - Session validation
    - File operation utilities
#>

# ============================================================================
# Response Helpers
# ============================================================================

<#
.SYNOPSIS
    Creates a standardized JSON response
#>
function New-WebHostFileExplorerResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('success', 'fail', 'error')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [hashtable]$Data = @{}
    )

    $response = @{
        status = $Status
        message = $Message
    }

    if ($Data.Count -gt 0) {
        $response.data = $Data
    }

    return $response | ConvertTo-Json -Depth 10 -Compress
}

<#
.SYNOPSIS
    Sends a JSON response to the client
.NOTES
    This function calls context_response from the caller's scope
#>
function Send-WebHostFileExplorerResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Response,

        [Parameter(Mandatory)]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [string]$JsonContent
    )

    # Call context_response from the calling scope (works when dot-sourced)
    context_response -Response $Response -StatusCode $StatusCode -String $JsonContent -ContentType "application/json"
}

# ============================================================================
# Session Validation
# ============================================================================

<#
.SYNOPSIS
    Validates user session and returns user ID
#>
function Test-WebHostFileExplorerSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $SessionData,

        [Parameter(Mandatory)]
        $Response
    )

    if (-not $SessionData -or -not $SessionData.UserID) {
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message 'User not authenticated'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 401 -JsonContent $json
        return $null
    }

    return $SessionData.UserID
}

# ============================================================================
# Path Resolution
# ============================================================================

<#
.SYNOPSIS
    Resolves a logical path to a physical path with authorization

.DESCRIPTION
    Wrapper around Path_Resolve.ps1 that provides consistent error handling

.PARAMETER LogicalPath
    The logical path (e.g., "User:me/Documents", "Bucket:abc-123")

.PARAMETER UserID
    The user requesting access

.PARAMETER Roles
    Array of user's roles

.PARAMETER RequiredPermission
    Required permission level: 'read', 'write', or 'owner'

.OUTPUTS
    Returns path resolution result or $null if failed (response already sent)
#>
function Resolve-WebHostFileExplorerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogicalPath,

        [Parameter(Mandatory)]
        [string]$UserID,

        [Parameter(Mandatory)]
        [array]$Roles,

        [Parameter(Mandatory)]
        $Response,

        [ValidateSet('read', 'write', 'owner')]
        [string]$RequiredPermission = 'read'
    )

    # Get path resolution script
    $pathResolveScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\utility\Path_Resolve.ps1"

    if (-not (Test-Path $pathResolveScript)) {
        $json = New-WebHostFileExplorerResponse -Status 'error' -Message 'Path resolution utility not found'
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode 500 -JsonContent $json
        return $null
    }

    # Resolve path
    $pathResult = & $pathResolveScript -LogicalPath $LogicalPath -UserID $UserID -Roles $Roles -RequiredPermission $RequiredPermission

    if (-not $pathResult.Success) {
        $statusCode = if ($pathResult.Message -like "*denied*" -or $pathResult.Message -like "*Insufficient*") { 403 } else { 400 }
        $json = New-WebHostFileExplorerResponse -Status 'fail' -Message $pathResult.Message
        Send-WebHostFileExplorerResponse -Response $Response -StatusCode $statusCode -JsonContent $json
        return $null
    }

    return $pathResult
}

# ============================================================================
# File Operations
# ============================================================================

<#
.SYNOPSIS
    Builds a file tree structure recursively
#>
function Get-WebHostFileExplorerTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
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
            $result.children += Get-WebHostFileExplorerTree -Directory $dir
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

<#
.SYNOPSIS
    Gets MIME type for a file extension
#>
function Get-WebHostFileExplorerMimeType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Extension
    )

    $ext = $Extension.ToLower()

    $mimeTypes = @{
        '.txt'  = 'text/plain'
        '.html' = 'text/html'
        '.css'  = 'text/css'
        '.js'   = 'application/javascript'
        '.json' = 'application/json'
        '.xml'  = 'application/xml'
        '.md'   = 'text/markdown'
        '.ps1'  = 'text/plain'
        '.psm1' = 'text/plain'
        '.psd1' = 'text/plain'
        '.yaml' = 'text/yaml'
        '.yml'  = 'text/yaml'
        '.jpg'  = 'image/jpeg'
        '.jpeg' = 'image/jpeg'
        '.png'  = 'image/png'
        '.gif'  = 'image/gif'
        '.svg'  = 'image/svg+xml'
        '.webp' = 'image/webp'
        '.bmp'  = 'image/bmp'
        '.pdf'  = 'application/pdf'
        '.mp3'  = 'audio/mpeg'
        '.wav'  = 'audio/wav'
        '.ogg'  = 'audio/ogg'
        '.mp4'  = 'video/mp4'
        '.webm' = 'video/webm'
        '.zip'  = 'application/zip'
    }

    if ($mimeTypes.ContainsKey($ext)) {
        return $mimeTypes[$ext]
    }

    return 'application/octet-stream'
}

<#
.SYNOPSIS
    Gets file category based on MIME type
#>
function Get-WebHostFileExplorerCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MimeType
    )

    if ($MimeType.StartsWith('text/') -or
        $MimeType -eq 'application/json' -or
        $MimeType -eq 'application/xml' -or
        $MimeType -eq 'application/javascript') {
        return 'text'
    }
    elseif ($MimeType.StartsWith('image/')) {
        return 'image'
    }
    elseif ($MimeType -eq 'application/pdf') {
        return 'pdf'
    }
    elseif ($MimeType.StartsWith('audio/')) {
        return 'audio'
    }
    elseif ($MimeType.StartsWith('video/')) {
        return 'video'
    }

    return 'unknown'
}

# ============================================================================
# Query Parameter Parsing
# ============================================================================

<#
.SYNOPSIS
    Parses URL query parameters into a hashtable
#>
function Get-WebHostFileExplorerQueryParams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Request
    )

    $queryParams = @{}

    if ($Request.Url.Query) {
        $Request.Url.Query.TrimStart('?').Split('&') | ForEach-Object {
            $parts = $_.Split('=')
            if ($parts.Length -eq 2) {
                $key = [System.Web.HttpUtility]::UrlDecode($parts[0])
                $value = [System.Web.HttpUtility]::UrlDecode($parts[1])
                $queryParams[$key] = $value
            }
        }
    }

    return $queryParams
}

# ============================================================================
# Error Handling
# ============================================================================

<#
.SYNOPSIS
    Handles errors consistently across endpoints
.NOTES
    Calls functions from the global scope (Write-PSWebHostLog, Get-PSWebHostErrorReport, context_response)
#>
function Send-WebHostFileExplorerError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ErrorRecord,

        [Parameter(Mandatory)]
        $Context,

        [Parameter(Mandatory)]
        $Request,

        [Parameter(Mandatory)]
        $Response,

        [Parameter(Mandatory)]
        $SessionData,

        [string]$Category = 'FileExplorer',

        [hashtable]$LogData = @{}
    )

    # Log error (works when dot-sourced)
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Error: $($ErrorRecord.Exception.Message)" -Data $LogData

    # Generate error report
    $Report = Get-PSWebHostErrorReport -ErrorRecord $ErrorRecord -Context $Context -Request $Request -sessiondata $SessionData

    # Send response
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}

# Note: This file is dot-sourced, not imported as a module
# Export-ModuleMember is not needed when dot-sourcing
