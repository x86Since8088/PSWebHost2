<#
.SYNOPSIS
    Retrieves user data folder paths based on application name and user ID.

.DESCRIPTION
    Searches across configured storage locations (from Data.UserDataStorage) to find user data folders.
    Structure: [storage location]\[user id]\[application name]\[subfolder]

    This ensures web access only interacts with authorized user spaces and prevents
    directory traversal attacks by validating all paths.

.PARAMETER UserID
    The user ID (required). Must be a valid user identifier.

.PARAMETER Application
    The application name or wildcard pattern (e.g., "file-explorer", "*").
    Default is "*" to match all applications.

.PARAMETER SubFolder
    Optional subfolder path within the application folder.

.PARAMETER CreateIfMissing
    If specified, creates the folder structure if it doesn't exist.

.PARAMETER ListAll
    If specified, returns all matching paths across all storage locations.
    Otherwise, returns only the first match.

.EXAMPLE
    .\UserData_Folder_Get.ps1 -UserID "user@example.com" -Application "file-explorer"
    Returns the file-explorer data folder for the specified user.

.EXAMPLE
    .\UserData_Folder_Get.ps1 -UserID "user123" -Application "*" -ListAll
    Returns all application folders for user123 across all storage locations.

.EXAMPLE
    .\UserData_Folder_Get.ps1 -UserID "admin" -Application "documents" -SubFolder "reports\2024" -CreateIfMissing
    Returns the reports\2024 subfolder, creating it if it doesn't exist.

.OUTPUTS
    System.IO.DirectoryInfo or array of DirectoryInfo objects
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserID,

    [Parameter(Mandatory = $false)]
    [string]$Application = "*",

    [Parameter(Mandatory = $false)]
    [string]$SubFolder,

    [switch]$CreateIfMissing,

    [switch]$ListAll
)

# Sanitize UserID to prevent directory traversal
$UserID = $UserID -replace '[\\/:*?"<>|]', '_'
if ($UserID -match '\.\.') {
    throw "Invalid UserID: '..' not allowed"
}

# Sanitize Application name
$Application = $Application -replace '[\\/:*?"<>|]', '_'
if ($Application -match '\.\.' -and $Application -ne '*') {
    throw "Invalid Application name: '..' not allowed"
}

# Sanitize SubFolder if provided
if ($SubFolder) {
    $SubFolder = $SubFolder -replace '[*?"<>|]', '_'
    if ($SubFolder -match '\.\.') {
        throw "Invalid SubFolder: '..' not allowed"
    }
    # Normalize path separators
    $SubFolder = $SubFolder -replace '/', '\'
}

# Get project root
if ($null -eq $Global:PSWebServer) {
    $ProjectRoot = Split-Path (Split-Path -Parent $PSScriptRoot)
} else {
    $ProjectRoot = $Global:PSWebServer.Project_Root.Path
}

# Load config if not already loaded
if ($null -eq $Global:PSWebServer.Config.Data.UserDataStorage) {
    $ConfigFile = Join-Path $ProjectRoot "config\settings.json"
    if (-not (Test-Path $ConfigFile)) {
        throw "Configuration file not found: $ConfigFile"
    }
    $Config = Get-Content $ConfigFile | ConvertFrom-Json
    $storageLocations = $Config.Data.UserDataStorage
} else {
    $storageLocations = $Global:PSWebServer.Config.Data.UserDataStorage
}

if (-not $storageLocations -or $storageLocations.Count -eq 0) {
    throw "No user data storage locations configured in Data.UserDataStorage"
}

$results = @()

foreach ($storagePath in $storageLocations) {
    # Resolve to absolute path
    $fullPath = if ([System.IO.Path]::IsPathRooted($storagePath)) {
        $storagePath
    } else {
        Join-Path $ProjectRoot $storagePath
    }

    if (-not (Test-Path $fullPath)) {
        Write-Verbose "Storage location does not exist: $fullPath"
        continue
    }

    # Build user path: [storage]\[userid]
    $userPath = Join-Path $fullPath $UserID

    # Check if user folder exists
    if (-not (Test-Path $userPath)) {
        if ($CreateIfMissing) {
            New-Item -Path $userPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created user folder: $userPath"
        } else {
            Write-Verbose "User folder does not exist: $userPath"
            continue
        }
    }

    # Find application folders
    if ($Application -eq '*') {
        # List all applications for this user
        $appFolders = Get-ChildItem -Path $userPath -Directory -ErrorAction SilentlyContinue
    } else {
        # Specific application
        $appPath = Join-Path $userPath $Application
        if (Test-Path $appPath) {
            $appFolders = @(Get-Item $appPath)
        } else {
            if ($CreateIfMissing) {
                New-Item -Path $appPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created application folder: $appPath"
                $appFolders = @(Get-Item $appPath)
            } else {
                Write-Verbose "Application folder does not exist: $appPath"
                $appFolders = @()
            }
        }
    }

    # Process each application folder
    foreach ($appFolder in $appFolders) {
        if ($SubFolder) {
            $targetPath = Join-Path $appFolder.FullName $SubFolder

            # Security check: ensure target path is still within the app folder
            $resolvedTarget = [System.IO.Path]::GetFullPath($targetPath)
            $resolvedApp = [System.IO.Path]::GetFullPath($appFolder.FullName)

            if (-not $resolvedTarget.StartsWith($resolvedApp, [StringComparison]::OrdinalIgnoreCase)) {
                Write-Warning "Security: SubFolder path escapes application directory. Skipping."
                continue
            }

            if (Test-Path $targetPath) {
                $results += Get-Item $targetPath
            } elseif ($CreateIfMissing) {
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created subfolder: $targetPath"
                $results += Get-Item $targetPath
            }
        } else {
            $results += $appFolder
        }
    }

    # If not listing all, return first match
    if ($results.Count -gt 0 -and -not $ListAll) {
        return $results[0]
    }
}

if ($ListAll) {
    return $results
} elseif ($results.Count -gt 0) {
    return $results[0]
} else {
    if (-not $CreateIfMissing) {
        Write-Verbose "No matching user data folders found."
    }
    return $null
}
