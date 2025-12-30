<#
.SYNOPSIS
    Migrates user data between applications or subfolders.

.DESCRIPTION
    Moves files from one application/subfolder to another within the same user's storage.
    Only operates within user folders under configured Data.UserDataStorage locations.

    Security: Ensures migration stays within authorized user storage boundaries.

.PARAMETER UserID
    The user ID (required).

.PARAMETER SourceApplication
    The source application name (required).

.PARAMETER DestinationApplication
    The destination application name. Defaults to SourceApplication if not specified.

.PARAMETER SourceSubFolder
    Optional source subfolder path.

.PARAMETER DestinationSubFolder
    Optional destination subfolder path. Defaults to SourceSubFolder if not specified.

.PARAMETER FilePattern
    File pattern to migrate (e.g., "*.txt", "report*"). Default is "*" (all files).

.PARAMETER Move
    Move files instead of copying them.

.PARAMETER Recurse
    Include subdirectories when migrating.

.EXAMPLE
    .\UserData_Folder_Migrate.ps1 -UserID "user@example.com" -SourceApplication "temp-uploads" -DestinationApplication "documents" -Move

.EXAMPLE
    .\UserData_Folder_Migrate.ps1 -UserID "admin" -SourceApplication "logs" -SourceSubFolder "2023" -DestinationSubFolder "archive\2023" -FilePattern "*.log"

.OUTPUTS
    Array of migrated file paths
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserID,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceApplication,

    [Parameter(Mandatory = $false)]
    [string]$DestinationApplication,

    [Parameter(Mandatory = $false)]
    [string]$SourceSubFolder,

    [Parameter(Mandatory = $false)]
    [string]$DestinationSubFolder,

    [Parameter(Mandatory = $false)]
    [string]$FilePattern = "*",

    [switch]$Move,

    [switch]$Recurse
)

# Default destination to source if not specified
if (-not $DestinationApplication) {
    $DestinationApplication = $SourceApplication
}
if (-not $DestinationSubFolder -and $SourceSubFolder) {
    $DestinationSubFolder = $SourceSubFolder
}

# Get the source folder
$getFolderScript = Join-Path $PSScriptRoot "UserData_Folder_Get.ps1"
if (-not (Test-Path $getFolderScript)) {
    throw "UserData_Folder_Get.ps1 not found at: $getFolderScript"
}

$sourceFolderParams = @{
    UserID = $UserID
    Application = $SourceApplication
}

if ($SourceSubFolder) {
    $sourceFolderParams.SubFolder = $SourceSubFolder
}

$sourceFolder = & $getFolderScript @sourceFolderParams

if (-not $sourceFolder) {
    throw "Source folder not found"
}

# Get the destination folder
$destFolderParams = @{
    UserID = $UserID
    Application = $DestinationApplication
    CreateIfMissing = $true
}

if ($DestinationSubFolder) {
    $destFolderParams.SubFolder = $DestinationSubFolder
}

$destFolder = & $getFolderScript @destFolderParams

if (-not $destFolder) {
    throw "Failed to get or create destination folder"
}

# Security check: both folders must be within user storage
$ProjectRoot = if ($null -eq $Global:PSWebServer) {
    Split-Path (Split-Path -Parent $PSScriptRoot)
} else {
    $Global:PSWebServer.Project_Root.Path
}

$storageLocations = if ($null -eq $Global:PSWebServer.Config.Data.UserDataStorage) {
    $ConfigFile = Join-Path $ProjectRoot "config\settings.json"
    $Config = Get-Content $ConfigFile | ConvertFrom-Json
    $Config.Data.UserDataStorage
} else {
    $Global:PSWebServer.Config.Data.UserDataStorage
}

$sourceWithinStorage = $false
$destWithinStorage = $false

foreach ($storagePath in $storageLocations) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($storagePath)) {
        $storagePath
    } else {
        Join-Path $ProjectRoot $storagePath
    }
    $resolvedStorage = [System.IO.Path]::GetFullPath($fullPath)
    $resolvedSource = [System.IO.Path]::GetFullPath($sourceFolder.FullName)
    $resolvedDest = [System.IO.Path]::GetFullPath($destFolder.FullName)

    if ($resolvedSource.StartsWith($resolvedStorage, [StringComparison]::OrdinalIgnoreCase)) {
        $sourceWithinStorage = $true
    }
    if ($resolvedDest.StartsWith($resolvedStorage, [StringComparison]::OrdinalIgnoreCase)) {
        $destWithinStorage = $true
    }
}

if (-not $sourceWithinStorage) {
    throw "Security: Source folder is not within authorized storage"
}
if (-not $destWithinStorage) {
    throw "Security: Destination folder is not within authorized storage"
}

# Prevent migrating to itself
if ($sourceFolder.FullName -eq $destFolder.FullName) {
    throw "Source and destination are the same"
}

# Get files to migrate
$getChildItemParams = @{
    Path = $sourceFolder.FullName
    Filter = $FilePattern
    File = $true
}

if ($Recurse) {
    $getChildItemParams.Recurse = $true
}

$files = Get-ChildItem @getChildItemParams -ErrorAction SilentlyContinue

if (-not $files -or $files.Count -eq 0) {
    Write-Warning "No files found matching pattern: $FilePattern"
    return @()
}

$migratedFiles = @()

foreach ($file in $files) {
    try {
        # Calculate relative path for recursive operations
        if ($Recurse) {
            $relativePath = $file.FullName.Substring($sourceFolder.FullName.Length).TrimStart('\', '/')
            $destPath = Join-Path $destFolder.FullName $relativePath
            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }
        } else {
            $destPath = Join-Path $destFolder.FullName $file.Name
        }

        # Check if destination file already exists
        if (Test-Path $destPath) {
            Write-Warning "Destination file already exists, skipping: $destPath"
            continue
        }

        # Perform migration
        if ($Move) {
            Move-Item -Path $file.FullName -Destination $destPath -Force
            Write-Verbose "Moved: $($file.FullName) -> $destPath"
        } else {
            Copy-Item -Path $file.FullName -Destination $destPath -Force
            Write-Verbose "Copied: $($file.FullName) -> $destPath"
        }

        $migratedFiles += $destPath
    }
    catch {
        Write-Warning "Failed to migrate $($file.FullName): $($_.Exception.Message)"
    }
}

Write-Verbose "Migrated $($migratedFiles.Count) files"
return $migratedFiles
