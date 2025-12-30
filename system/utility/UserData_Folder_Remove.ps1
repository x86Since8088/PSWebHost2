<#
.SYNOPSIS
    Removes files or folders from a user's application storage.

.DESCRIPTION
    Deletes files or entire folders from a user's application storage.
    Structure: [storage location]\[user id]\[application name]\[subfolder]

    Security: Only operates within authorized user storage boundaries.

.PARAMETER UserID
    The user ID (required).

.PARAMETER Application
    The application name (required).

.PARAMETER SubFolder
    Optional subfolder path to remove.

.PARAMETER Name
    Optional specific file name to remove.

.PARAMETER FilePattern
    File pattern to remove (e.g., "*.tmp", "log*"). Only used if -Name is not specified.

.PARAMETER RemoveFolder
    Remove the entire folder (application or subfolder) and its contents.

.PARAMETER Recurse
    Remove files recursively when using FilePattern.

.PARAMETER Force
    Force removal without confirmation.

.EXAMPLE
    .\UserData_Folder_Remove.ps1 -UserID "user@example.com" -Application "temp" -Name "upload.tmp"

.EXAMPLE
    .\UserData_Folder_Remove.ps1 -UserID "admin" -Application "logs" -SubFolder "2023" -RemoveFolder -Force

.EXAMPLE
    .\UserData_Folder_Remove.ps1 -UserID "user123" -Application "cache" -FilePattern "*.cache" -Recurse

.OUTPUTS
    Array of removed file/folder paths
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserID,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Application,

    [Parameter(Mandatory = $false)]
    [string]$SubFolder,

    [Parameter(Mandatory = $false)]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$FilePattern = "*",

    [switch]$RemoveFolder,

    [switch]$Recurse,

    [switch]$Force
)

# Get the target folder
$getFolderScript = Join-Path $PSScriptRoot "UserData_Folder_Get.ps1"
if (-not (Test-Path $getFolderScript)) {
    throw "UserData_Folder_Get.ps1 not found at: $getFolderScript"
}

$getFolderParams = @{
    UserID = $UserID
    Application = $Application
}

if ($SubFolder) {
    $getFolderParams.SubFolder = $SubFolder
}

$targetFolder = & $getFolderScript @getFolderParams

if (-not $targetFolder) {
    Write-Warning "Target folder not found"
    return @()
}

# Security check: folder must be within user storage
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

$withinStorage = $false
foreach ($storagePath in $storageLocations) {
    $fullPath = if ([System.IO.Path]::IsPathRooted($storagePath)) {
        $storagePath
    } else {
        Join-Path $ProjectRoot $storagePath
    }
    $resolvedStorage = [System.IO.Path]::GetFullPath($fullPath)
    $resolvedTarget = [System.IO.Path]::GetFullPath($targetFolder.FullName)

    if ($resolvedTarget.StartsWith($resolvedStorage, [StringComparison]::OrdinalIgnoreCase)) {
        $withinStorage = $true
        break
    }
}

if (-not $withinStorage) {
    throw "Security: Target folder is not within authorized storage"
}

$removedItems = @()

# Remove entire folder
if ($RemoveFolder) {
    if (-not $Force) {
        $confirmation = Read-Host "Remove entire folder '$($targetFolder.FullName)' and all contents? (Y/N)"
        if ($confirmation -ne 'Y') {
            Write-Host "Operation cancelled"
            return @()
        }
    }

    try {
        Remove-Item -Path $targetFolder.FullName -Recurse -Force
        Write-Verbose "Removed folder: $($targetFolder.FullName)"
        $removedItems += $targetFolder.FullName
    }
    catch {
        throw "Failed to remove folder: $($_.Exception.Message)"
    }
}
# Remove specific file
elseif ($Name) {
    $Name = $Name -replace '[\\/:*?"<>|]', '_'
    if ($Name -match '\.\.') {
        throw "Invalid Name: '..' not allowed"
    }

    $filePath = Join-Path $targetFolder.FullName $Name

    # Security check
    $resolvedFile = [System.IO.Path]::GetFullPath($filePath)
    $resolvedFolder = [System.IO.Path]::GetFullPath($targetFolder.FullName)

    if (-not $resolvedFile.StartsWith($resolvedFolder, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Security: File path escapes target directory"
    }

    if (-not (Test-Path $filePath)) {
        Write-Warning "File not found: $filePath"
        return @()
    }

    if (-not $Force) {
        $confirmation = Read-Host "Remove file '$filePath'? (Y/N)"
        if ($confirmation -ne 'Y') {
            Write-Host "Operation cancelled"
            return @()
        }
    }

    try {
        Remove-Item -Path $filePath -Force
        Write-Verbose "Removed file: $filePath"
        $removedItems += $filePath
    }
    catch {
        throw "Failed to remove file: $($_.Exception.Message)"
    }
}
# Remove files by pattern
else {
    $getChildItemParams = @{
        Path = $targetFolder.FullName
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

    if (-not $Force) {
        $confirmation = Read-Host "Remove $($files.Count) file(s) matching '$FilePattern'? (Y/N)"
        if ($confirmation -ne 'Y') {
            Write-Host "Operation cancelled"
            return @()
        }
    }

    foreach ($file in $files) {
        try {
            Remove-Item -Path $file.FullName -Force
            Write-Verbose "Removed file: $($file.FullName)"
            $removedItems += $file.FullName
        }
        catch {
            Write-Warning "Failed to remove $($file.FullName): $($_.Exception.Message)"
        }
    }
}

Write-Verbose "Removed $($removedItems.Count) item(s)"
return $removedItems
