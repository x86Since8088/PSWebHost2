<#
.SYNOPSIS
    Renames files or folders in a user's application storage.

.DESCRIPTION
    Renames files or subfolders within a user's application storage.
    Structure: [storage location]\[user id]\[application name]\[subfolder]

    Security: Only operates within authorized user storage boundaries.

.PARAMETER UserID
    The user ID (required).

.PARAMETER Application
    The application name (required).

.PARAMETER SubFolder
    Optional subfolder path containing the item to rename.

.PARAMETER OldName
    The current name of the file or folder (required).

.PARAMETER NewName
    The new name for the file or folder (required).

.PARAMETER IsFolder
    Specify if renaming a folder instead of a file.

.PARAMETER Force
    Overwrite if NewName already exists.

.EXAMPLE
    .\UserData_Folder_Rename.ps1 -UserID "user@example.com" -Application "documents" -OldName "draft.txt" -NewName "final.txt"

.EXAMPLE
    .\UserData_Folder_Rename.ps1 -UserID "admin" -Application "projects" -SubFolder "2024" -OldName "Q1" -NewName "Quarter1" -IsFolder

.OUTPUTS
    System.IO.FileInfo or DirectoryInfo of the renamed item
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

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OldName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NewName,

    [switch]$IsFolder,

    [switch]$Force
)

# Sanitize names
$OldName = $OldName -replace '[\\/:*?"<>|]', '_'
$NewName = $NewName -replace '[\\/:*?"<>|]', '_'

if ($OldName -match '\.\.' -or $NewName -match '\.\.') {
    throw "Invalid name: '..' not allowed"
}

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
    throw "Target folder not found"
}

# Build old and new paths
$oldPath = Join-Path $targetFolder.FullName $OldName
$newPath = Join-Path $targetFolder.FullName $NewName

# Security checks
$resolvedOld = [System.IO.Path]::GetFullPath($oldPath)
$resolvedNew = [System.IO.Path]::GetFullPath($newPath)
$resolvedFolder = [System.IO.Path]::GetFullPath($targetFolder.FullName)

if (-not $resolvedOld.StartsWith($resolvedFolder, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Security: OldName path escapes target directory"
}

if (-not $resolvedNew.StartsWith($resolvedFolder, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Security: NewName path escapes target directory"
}

# Verify old item exists
if (-not (Test-Path $oldPath)) {
    throw "Item not found: $oldPath"
}

# Check if it's the correct type
$oldItem = Get-Item $oldPath
if ($IsFolder -and -not $oldItem.PSIsContainer) {
    throw "Item is not a folder: $oldPath"
}
if (-not $IsFolder -and $oldItem.PSIsContainer) {
    throw "Item is not a file: $oldPath (use -IsFolder to rename folders)"
}

# Check if new name already exists
if (Test-Path $newPath) {
    if (-not $Force) {
        throw "Item already exists at new path: $newPath. Use -Force to overwrite."
    } else {
        Remove-Item -Path $newPath -Recurse -Force
        Write-Verbose "Removed existing item at: $newPath"
    }
}

# Perform rename
try {
    Rename-Item -Path $oldPath -NewName $NewName -Force
    Write-Verbose "Renamed: $oldPath -> $newPath"
    return Get-Item $newPath
}
catch {
    throw "Failed to rename item: $($_.Exception.Message)"
}
