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
    This function calls context_response from the global scope using Get-Command
#>
function Send-WebHostFileExplorerResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Response,

        [Parameter(Mandatory)]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [string]$JsonContent,

        [switch]$Test
    )

    if ($Test -or ($Response -is [string] -and $Response -eq 'test')) {
        # Test mode: Display response to console
        $color = if ($StatusCode -ge 200 -and $StatusCode -lt 300) { 'Green' } elseif ($StatusCode -ge 400) { 'Red' } else { 'Yellow' }
        Write-Host "`n=== Response: $StatusCode ===" -ForegroundColor $color
        $JsonContent | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
    } else {
        # Call context_response from global scope (module isolation)
        context_response -Response $Response -StatusCode $StatusCode -String $JsonContent -ContentType "application/json"
    }
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
    Calls functions from the global scope using Get-Command (Write-PSWebHostLog, Get-PSWebHostErrorReport, context_response)
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

    # Log error (call from global scope for module isolation)
    Write-PSWebHostLog -Severity 'Error' -Category $Category -Message "Error: $($ErrorRecord.Exception.Message)" -Data $LogData

    # Generate error report (call from global scope)
    $Report = Get-PSWebHostErrorReport -ErrorRecord $ErrorRecord -Context $Context -Request $Request -sessiondata $SessionData

    # Send response (call from global scope)
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}

# ============================================================================
# Trash Bin & Undo System
# ============================================================================

<#
.SYNOPSIS
    Gets the trash bin path for a user and operation

.DESCRIPTION
    Creates directory structure: PsWebHost_Data\trash_bin\[userid]\[operation_id]\
#>
function Get-WebHostFileExplorerTrashPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserID,

        [Parameter(Mandatory)]
        [string]$OperationID
    )

    # Get PsWebHost_Data path
    $dataRoot = if ($Global:PSWebServer -and $Global:PSWebServer.DataPath) {
        $Global:PSWebServer.DataPath
    } else {
        Join-Path $PSScriptRoot "..\..\..\..\PsWebHost_Data"
    }

    # Build trash path: PsWebHost_Data\trash_bin\[userid]\[operation_id]\
    $trashPath = Join-Path $dataRoot "trash_bin"
    $trashPath = Join-Path $trashPath $UserID
    $trashPath = Join-Path $trashPath $OperationID

    # Create directory if it doesn't exist
    if (-not (Test-Path $trashPath)) {
        New-Item -Path $trashPath -ItemType Directory -Force | Out-Null
    }

    return $trashPath
}

<#
.SYNOPSIS
    Saves undo metadata to user's undo.json file

.DESCRIPTION
    Appends operation metadata to PsWebHost_Data\apps\WebhostFileExplorer\UserMetadata\[userid]\undo.json
#>
function Save-WebHostFileExplorerUndoData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserID,

        [Parameter(Mandatory)]
        [hashtable]$UndoOperation
    )

    # Get PsWebHost_Data path
    $dataRoot = if ($Global:PSWebServer -and $Global:PSWebServer.DataPath) {
        $Global:PSWebServer.DataPath
    } else {
        Join-Path $PSScriptRoot "..\..\..\..\PsWebHost_Data"
    }

    # Build metadata path: PsWebHost_Data\apps\WebhostFileExplorer\UserMetadata\[userid]\
    $metadataDir = Join-Path $dataRoot "apps"
    $metadataDir = Join-Path $metadataDir "WebhostFileExplorer"
    $metadataDir = Join-Path $metadataDir "UserMetadata"
    $metadataDir = Join-Path $metadataDir $UserID

    # Create directory if it doesn't exist
    if (-not (Test-Path $metadataDir)) {
        New-Item -Path $metadataDir -ItemType Directory -Force | Out-Null
    }

    $undoFilePath = Join-Path $metadataDir "undo.json"

    # Load existing undo data or create new
    $undoData = if (Test-Path $undoFilePath) {
        Get-Content $undoFilePath -Raw | ConvertFrom-Json
        # Convert to hashtable for manipulation
        @{ operations = @($undoData.operations) }
    } else {
        @{ operations = @() }
    }

    # Add new operation to beginning (most recent first)
    $undoData.operations = @($UndoOperation) + $undoData.operations

    # Limit to last 50 operations
    if ($undoData.operations.Count -gt 50) {
        $undoData.operations = $undoData.operations[0..49]
    }

    # Save to file
    $undoData | ConvertTo-Json -Depth 10 | Set-Content -Path $undoFilePath -Force

    # Log from global scope (module isolation)
    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Saved undo data for operation: $($UndoOperation.id)" -Data @{
        UserID = $UserID
        OperationID = $UndoOperation.id
        Action = $UndoOperation.action
        ItemCount = $UndoOperation.itemCount
    }

    return $undoFilePath
}

<#
.SYNOPSIS
    Gets user information from session data

.DESCRIPTION
    Retrieves username and email from session data if available
#>
function Get-WebHostFileExplorerUserInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserID,

        $SessionData = $null
    )

    $userInfo = @{
        UserID = $UserID
        Username = $UserID  # Default to UserID
        Email = $null
    }

    try {
        # Try to get username from session data
        if ($SessionData) {
            if ($SessionData.Username) {
                $userInfo.Username = $SessionData.Username
            }
            if ($SessionData.Email) {
                $userInfo.Email = $SessionData.Email
            }
            # Alternative session data fields
            if ($SessionData.User -and $SessionData.User.Username) {
                $userInfo.Username = $SessionData.User.Username
            }
            if ($SessionData.User -and $SessionData.User.Email) {
                $userInfo.Email = $SessionData.User.Email
            }
        }
    }
    catch {
        # If session data parsing fails, just use defaults
        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to get user info from session: $($_.Exception.Message)"
    }

    return $userInfo
}

<#
.SYNOPSIS
    Detects if a path is on a remote volume or network share

.DESCRIPTION
    Checks if path is on different volume than system drive or UNC path
#>
function Test-WebHostFileExplorerRemoteVolume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PhysicalPath
    )

    try {
        # Get system drive (where PsWebHost_Data is located)
        $dataRoot = if ($Global:PSWebServer -and $Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\..\..\PsWebHost_Data"
        }

        # Ensure data root path exists
        if (-not (Test-Path $dataRoot)) {
            # Default to C: if data root doesn't exist
            $systemDrive = 'C'
        }
        else {
            $systemDrive = (Get-Item $dataRoot).PSDrive.Name
        }

        # Check if UNC path (network share)
        if ($PhysicalPath -match '^\\\\') {
            # Extract UNC root (\\server\share)
            $uncRoot = $PhysicalPath -replace '^(\\\\[^\\]+\\[^\\]+).*', '$1'
            return @{
                IsRemote = $true
                Type = 'UNC'
                Root = $uncRoot
                AccessMethod = 'WebHostSMBClient'
            }
        }

        # Check if different drive letter
        if (Test-Path $PhysicalPath) {
            $item = Get-Item $PhysicalPath
            $itemDrive = $item.PSDrive.Name

            if ($itemDrive -ne $systemDrive) {
                return @{
                    IsRemote = $true
                    Type = 'Volume'
                    Root = "${itemDrive}:\"
                    AccessMethod = 'Direct'
                }
            }
        }
        else {
            # Path doesn't exist - try to extract drive from path string
            if ($PhysicalPath -match '^([A-Z]):') {
                $itemDrive = $matches[1]
                if ($itemDrive -ne $systemDrive) {
                    return @{
                        IsRemote = $true
                        Type = 'Volume'
                        Root = "${itemDrive}:\"
                        AccessMethod = 'Direct'
                    }
                }
            }
        }

        # Check if SSH/SFTP path (would be in logical path format)
        # This is a placeholder - actual detection would be in logical path
        # Format: ssh|hostname|/path/to/file

        return @{
            IsRemote = $false
            Type = 'Local'
            Root = $null
            AccessMethod = 'Direct'
        }
    }
    catch {
        # On any error, assume local
        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Error detecting remote volume, assuming local: $($_.Exception.Message)" -Data @{
            PhysicalPath = $PhysicalPath
            Error = $_.Exception.Message
        }

        return @{
            IsRemote = $false
            Type = 'Local'
            Root = $null
            AccessMethod = 'Direct'
        }
    }
}

<#
.SYNOPSIS
    Gets or creates trash bin path for remote storage locations

.DESCRIPTION
    For remote volumes/shares, creates .pswebhost/trash_bin on that location
    Registers remote trash locations in trash_bin_remote_locations.json
#>
function Get-WebHostFileExplorerRemoteTrashPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RemoteRoot,

        [Parameter(Mandatory)]
        [string]$UserID,

        [Parameter(Mandatory)]
        [string]$OperationID,

        [string]$AccessMethod = 'Direct'
    )

    try {
        # Build remote trash path: [RemoteRoot]\.pswebhost\trash_bin\[userid]\[operation_id]\
        $remoteTrashPath = Join-Path $RemoteRoot ".pswebhost"
        $remoteTrashPath = Join-Path $remoteTrashPath "trash_bin"
        $remoteTrashPath = Join-Path $remoteTrashPath $UserID
        $remoteTrashPath = Join-Path $remoteTrashPath $OperationID

        # Create directory if it doesn't exist
        if (-not (Test-Path $remoteTrashPath)) {
            New-Item -Path $remoteTrashPath -ItemType Directory -Force | Out-Null
        }

        # Register remote trash location
        $dataRoot = if ($Global:PSWebServer -and $Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\..\..\PsWebHost_Data"
        }

        $masterTrashPath = Join-Path $dataRoot "trash_bin"
        if (-not (Test-Path $masterTrashPath)) {
            New-Item -Path $masterTrashPath -ItemType Directory -Force | Out-Null
        }

        $remoteRegistryPath = Join-Path $masterTrashPath "trash_bin_remote_locations.json"

        # Load or create registry
        $registry = if (Test-Path $remoteRegistryPath) {
            try {
                $registryContent = Get-Content $remoteRegistryPath -Raw | ConvertFrom-Json
                # Convert to hashtable for manipulation
                @{ locations = @($registryContent.locations) }
            }
            catch {
                Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to load remote registry, creating new: $($_.Exception.Message)"
                @{ locations = @() }
            }
        } else {
            @{ locations = @() }
        }

        # Add this location if not already registered
        $locationKey = "$RemoteRoot|$UserID|$OperationID"
        $existingLocation = $registry.locations | Where-Object { $_.key -eq $locationKey }

        if (-not $existingLocation) {
            $registry.locations += @{
                key = $locationKey
                remoteRoot = $RemoteRoot
                trashPath = $remoteTrashPath
                userID = $UserID
                operationID = $OperationID
                accessMethod = $AccessMethod
                registeredAt = Get-Date -Format "o"
            }

            # Save registry
            try {
                $registry | ConvertTo-Json -Depth 10 | Set-Content -Path $remoteRegistryPath -Force
            }
            catch {
                Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to save remote registry: $($_.Exception.Message)"
            }
        }

        return $remoteTrashPath
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to create remote trash path: $($_.Exception.Message)" -Data @{
            RemoteRoot = $RemoteRoot
            UserID = $UserID
            OperationID = $OperationID
            Error = $_.Exception.Message
        }
        throw
    }
}

<#
.SYNOPSIS
    Writes metadata file for deleted item

.DESCRIPTION
    Creates a .metadata.json file alongside the trashed item
    MUST be written successfully BEFORE moving the file to trash
#>
function Write-WebHostFileExplorerTrashMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TrashPath,

        [Parameter(Mandatory)]
        [string]$OriginalPath,

        [Parameter(Mandatory)]
        [string]$LogicalPath,

        [Parameter(Mandatory)]
        [hashtable]$UserInfo,

        [Parameter(Mandatory)]
        [string]$OperationID,

        [string]$Action = 'delete',

        [string]$ItemType = 'file'
    )

    $metadataWriteStart = Get-Date

    # Build metadata file path (same location as trashed item, with .metadata.json extension)
    $metadataPath = "$TrashPath.metadata.json"

    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[METADATA] START - Writing metadata file" -Data @{
        OperationID = $OperationID
        MetadataPath = $metadataPath
        OriginalPath = $OriginalPath
    }

    # Create metadata object
    $metadata = @{
        operationID = $OperationID
        timestamp = Get-Date -Format "o"
        action = $Action
        deletedBy = @{
            userID = $UserInfo.UserID
            username = $UserInfo.Username
            email = $UserInfo.Email
        }
        original = @{
            path = $OriginalPath
            logicalPath = $LogicalPath
            type = $ItemType
        }
        trash = @{
            path = $TrashPath
            fileName = Split-Path $TrashPath -Leaf
        }
    }

    try {
        # Convert to JSON
        $jsonStart = Get-Date
        $metadataJson = $metadata | ConvertTo-Json -Depth 10
        $jsonDuration = (Get-Date) - $jsonStart

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[METADATA] JSON serialization complete" -Data @{
            OperationID = $OperationID
            JsonLength = $metadataJson.Length
            DurationMs = [int]$jsonDuration.TotalMilliseconds
        }

        # Write metadata file (this MUST succeed before moving the file)
        $writeStart = Get-Date
        $metadataJson | Set-Content -Path $metadataPath -Force -ErrorAction Stop
        $writeDuration = (Get-Date) - $writeStart

        $totalDuration = (Get-Date) - $metadataWriteStart

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[METADATA] STOP - Metadata written successfully" -Data @{
            OperationID = $OperationID
            MetadataPath = $metadataPath
            OriginalPath = $OriginalPath
            FileSize = (Get-Item $metadataPath).Length
            WriteDurationMs = [int]$writeDuration.TotalMilliseconds
            TotalDurationMs = [int]$totalDuration.TotalMilliseconds
        }

        return $metadataPath
    }
    catch {
        $totalDuration = (Get-Date) - $metadataWriteStart

        Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "[METADATA] STOP - Failed to write metadata: $($_.Exception.Message)" -Data @{
            OperationID = $OperationID
            MetadataPath = $metadataPath
            OriginalPath = $OriginalPath
            Error = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
            TotalDurationMs = [int]$totalDuration.TotalMilliseconds
        }
        throw "Failed to write metadata file: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Moves files/folders to trash bin instead of permanent deletion

.DESCRIPTION
    - Creates unique operation ID
    - Detects remote volumes and uses .pswebhost/trash_bin on those locations
    - Writes metadata file BEFORE moving each file
    - Registers remote trash locations
    - Returns undo metadata

.OUTPUTS
    Hashtable with operation metadata for undo.json
#>
function Move-WebHostFileExplorerToTrash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserID,

        [Parameter(Mandatory)]
        [array]$Items,  # Array of hashtables with PhysicalPath, LogicalPath, Type

        [string]$Action = 'delete',

        $SessionData = $null
    )

    try {
        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Starting trash operation" -Data @{
            UserID = $UserID
            ItemCount = $Items.Count
            Action = $Action
        }

        # Generate unique operation ID
        $operationID = [guid]::NewGuid().ToString()
        $timestamp = Get-Date -Format "o"

        # Get user information
        $userInfo = Get-WebHostFileExplorerUserInfo -UserID $UserID -SessionData $SessionData

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "User info retrieved" -Data @{
            UserID = $userInfo.UserID
            Username = $userInfo.Username
            Email = $userInfo.Email
        }

        # Track moved items for undo metadata
        $movedItems = @()
        $errors = @()
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Failed to initialize trash operation: $($_.Exception.Message)" -Data @{
            UserID = $UserID
            Error = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
        }
        throw
    }

    foreach ($item in $Items) {
        $itemStartTime = Get-Date
        $itemIndex = $Items.IndexOf($item) + 1

        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] START processing item $itemIndex of $($Items.Count)" -Data @{
            OperationID = $operationID
            ItemIndex = $itemIndex
            TotalItems = $Items.Count
            LogicalPath = $item.LogicalPath
            PhysicalPath = $item.PhysicalPath
        }

        try {
            $physicalPath = $item.PhysicalPath
            $logicalPath = $item.LogicalPath

            # Step 1: Check if file/folder exists
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 1: Checking if path exists" -Data @{
                OperationID = $operationID
                PhysicalPath = $physicalPath
            }

            if (-not (Test-Path -Path $physicalPath)) {
                $errors += @{
                    path = $item.LogicalPath
                    error = "File or folder not found"
                }
                Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "[DELETE] SKIP: File not found" -Data @{
                    OperationID = $operationID
                    LogicalPath = $logicalPath
                }
                continue
            }

            $itemType = if (Test-Path -Path $physicalPath -PathType Container) { 'folder' } else { 'file' }
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 1: COMPLETE - Path exists" -Data @{
                OperationID = $operationID
                Type = $itemType
            }

            # Step 2: Detect if on remote volume
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 2: Detecting remote volume" -Data @{
                OperationID = $operationID
                PhysicalPath = $physicalPath
            }

            $remoteCheckStart = Get-Date
            $remoteCheck = Test-WebHostFileExplorerRemoteVolume -PhysicalPath $physicalPath
            $remoteCheckDuration = (Get-Date) - $remoteCheckStart

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 2: COMPLETE - Remote check" -Data @{
                OperationID = $operationID
                IsRemote = $remoteCheck.IsRemote
                Type = $remoteCheck.Type
                Root = $remoteCheck.Root
                AccessMethod = $remoteCheck.AccessMethod
                DurationMs = [int]$remoteCheckDuration.TotalMilliseconds
            }

            # Step 3: Determine trash path
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 3: Determining trash path" -Data @{
                OperationID = $operationID
                IsRemote = $remoteCheck.IsRemote
            }

            $trashPathStart = Get-Date
            if ($remoteCheck.IsRemote) {
                $trashRoot = Get-WebHostFileExplorerRemoteTrashPath `
                    -RemoteRoot $remoteCheck.Root `
                    -UserID $UserID `
                    -OperationID $operationID `
                    -AccessMethod $remoteCheck.AccessMethod
            }
            else {
                $trashRoot = Get-WebHostFileExplorerTrashPath -UserID $UserID -OperationID $operationID
            }
            $trashPathDuration = (Get-Date) - $trashPathStart

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 3: COMPLETE - Trash path determined" -Data @{
                OperationID = $operationID
                TrashRoot = $trashRoot
                DurationMs = [int]$trashPathDuration.TotalMilliseconds
            }

            # Step 4: Build trash destination and handle conflicts
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 4: Building trash destination" -Data @{
                OperationID = $operationID
            }

            $fileName = Split-Path $physicalPath -Leaf
            $trashDestination = Join-Path $trashRoot $fileName
            $counter = 1
            while (Test-Path $trashDestination) {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                $extension = [System.IO.Path]::GetExtension($fileName)
                $fileName = "${baseName}_${counter}${extension}"
                $trashDestination = Join-Path $trashRoot $fileName
                $counter++
            }

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 4: COMPLETE - Destination ready" -Data @{
                OperationID = $operationID
                TrashDestination = $trashDestination
                ConflictResolution = if ($counter -gt 1) { "Renamed to avoid conflict (counter: $($counter-1))" } else { "No conflict" }
            }

            # Step 5: Write metadata file
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 5: Writing metadata file" -Data @{
                OperationID = $operationID
                MetadataPath = "$trashDestination.metadata.json"
            }

            $metadataStart = Get-Date
            $metadataPath = Write-WebHostFileExplorerTrashMetadata `
                -TrashPath $trashDestination `
                -OriginalPath $physicalPath `
                -LogicalPath $logicalPath `
                -UserInfo $userInfo `
                -OperationID $operationID `
                -Action $Action `
                -ItemType $itemType
            $metadataDuration = (Get-Date) - $metadataStart

            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 5: COMPLETE - Metadata written" -Data @{
                OperationID = $operationID
                MetadataPath = $metadataPath
                DurationMs = [int]$metadataDuration.TotalMilliseconds
            }

            # Step 6: Move file to trash
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] Step 6: START - Moving file to trash" -Data @{
                OperationID = $operationID
                Source = $physicalPath
                Destination = $trashDestination
            }

            $moveStart = Get-Date
            try {
                Move-Item -Path $physicalPath -Destination $trashDestination -Force -ErrorAction Stop
                $moveSuccess = $true
                $moveError = $null
            }
            catch {
                $moveSuccess = $false
                $moveError = $_.Exception.Message
                throw
            }
            finally {
                $moveDuration = (Get-Date) - $moveStart

                Write-PSWebHostLog -Severity $(if ($moveSuccess) { 'Info' } else { 'Error' }) -Category 'FileExplorer' -Message "[DELETE] Step 6: STOP - Move file operation" -Data @{
                    OperationID = $operationID
                    Success = $moveSuccess
                    Source = $physicalPath
                    Destination = $trashDestination
                    DurationMs = [int]$moveDuration.TotalMilliseconds
                    Error = $moveError
                }
            }

            # Add to moved items
            $movedItems += @{
                originalPath = $physicalPath
                logicalPath = $logicalPath
                trashPath = $trashDestination
                metadataPath = $metadataPath
                type = $itemType
                trashFileName = $fileName
                isRemote = $remoteCheck.IsRemote
                accessMethod = $remoteCheck.AccessMethod
            }

            $itemDuration = (Get-Date) - $itemStartTime
            Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "[DELETE] COMPLETE: Item $itemIndex moved to trash successfully" -Data @{
                OperationID = $operationID
                ItemIndex = $itemIndex
                LogicalPath = $logicalPath
                TrashPath = $trashDestination
                TotalDurationMs = [int]$itemDuration.TotalMilliseconds
            }
        }
        catch {
            $itemDuration = (Get-Date) - $itemStartTime
            $errors += @{
                path = $item.LogicalPath
                error = $_.Exception.Message
            }
            Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "[DELETE] FAILED: Item $itemIndex - $($_.Exception.Message)" -Data @{
                UserID = $UserID
                OperationID = $operationID
                ItemIndex = $itemIndex
                LogicalPath = $item.LogicalPath
                Error = $_.Exception.Message
                StackTrace = $_.ScriptStackTrace
                TotalDurationMs = [int]$itemDuration.TotalMilliseconds
            }
        }
    }

    # Create undo metadata
    $undoOperation = @{
        id = $operationID
        timestamp = $timestamp
        action = $Action
        itemCount = $movedItems.Count
        deletedBy = @{
            userID = $userInfo.UserID
            username = $userInfo.Username
            email = $userInfo.Email
        }
        items = $movedItems
    }

    return @{
        operation = $undoOperation
        movedItems = $movedItems
        errors = $errors
    }
}

# Note: This is a PowerShell module (.psm1) imported via Import-TrackedModule
# Functions are exported via the .psd1 manifest's FunctionsToExport list
