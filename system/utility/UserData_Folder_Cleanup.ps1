<#
.SYNOPSIS
    Cleans up old files from a user's application storage.

.DESCRIPTION
    Deletes files older than a specified age and optionally matching a filename pattern.
    Structure: [storage location]\[user id]\[application name]\[subfolder]

    Security: Only operates within authorized user storage boundaries.

.PARAMETER UserID
    The user ID (required).

.PARAMETER Application
    The application name (required).

.PARAMETER SubFolder
    Optional subfolder path to clean up.

.PARAMETER OlderThanDays
    Remove files older than this many days. Default is 30.

.PARAMETER OlderThanHours
    Alternative: Remove files older than this many hours.

.PARAMETER FilePattern
    File pattern regex to match (e.g., "\.log$", "temp.*"). Default is ".*" (all files).

.PARAMETER Recurse
    Clean up files recursively in subdirectories.

.PARAMETER WhatIf
    Show what would be deleted without actually deleting.

.PARAMETER Force
    Force cleanup without confirmation.

.EXAMPLE
    .\UserData_Folder_Cleanup.ps1 -UserID "user@example.com" -Application "logs" -OlderThanDays 90 -FilePattern "\.log$"

.EXAMPLE
    .\UserData_Folder_Cleanup.ps1 -UserID "admin" -Application "temp" -OlderThanHours 24 -Force

.EXAMPLE
    .\UserData_Folder_Cleanup.ps1 -UserID "user123" -Application "cache" -OlderThanDays 7 -WhatIf

.OUTPUTS
    Array of cleaned up file paths
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
    [int]$OlderThanDays = 30,

    [Parameter(Mandatory = $false)]
    [int]$OlderThanHours,

    [Parameter(Mandatory = $false)]
    [string]$FilePattern = ".*",

    [switch]$Recurse,

    [switch]$WhatIf,

    [switch]$Force
)

# Calculate cutoff date
if ($OlderThanHours) {
    $cutoffDate = (Get-Date).AddHours(-$OlderThanHours)
    $ageDescription = "$OlderThanHours hours"
} else {
    $cutoffDate = (Get-Date).AddDays(-$OlderThanDays)
    $ageDescription = "$OlderThanDays days"
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

# Get all files
$getChildItemParams = @{
    Path = $targetFolder.FullName
    File = $true
}

if ($Recurse) {
    $getChildItemParams.Recurse = $true
}

$allFiles = Get-ChildItem @getChildItemParams -ErrorAction SilentlyContinue

if (-not $allFiles -or $allFiles.Count -eq 0) {
    Write-Verbose "No files found in target folder"
    return @()
}

# Filter by age and pattern
$filesToDelete = $allFiles | Where-Object {
    $_.LastWriteTime -lt $cutoffDate -and $_.Name -match $FilePattern
}

if (-not $filesToDelete -or $filesToDelete.Count -eq 0) {
    Write-Verbose "No files found matching criteria (older than $ageDescription and pattern '$FilePattern')"
    return @()
}

# Calculate total size
$totalSize = ($filesToDelete | Measure-Object -Property Length -Sum).Sum
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Host "Found $($filesToDelete.Count) file(s) to clean up (Total: $totalSizeMB MB)"
Write-Host "Files older than $ageDescription matching pattern: $FilePattern"

if ($WhatIf) {
    Write-Host "`n[WhatIf] Would delete the following files:"
    foreach ($file in $filesToDelete) {
        $age = ((Get-Date) - $file.LastWriteTime).TotalDays
        $sizeMB = [math]::Round($file.Length / 1MB, 2)
        Write-Host "  - $($file.FullName) (Age: $([math]::Round($age, 1)) days, Size: $sizeMB MB)"
    }
    return @()
}

if (-not $Force) {
    $confirmation = Read-Host "`nProceed with cleanup of $($filesToDelete.Count) file(s)? (Y/N)"
    if ($confirmation -ne 'Y') {
        Write-Host "Operation cancelled"
        return @()
    }
}

$cleanedFiles = @()

foreach ($file in $filesToDelete) {
    try {
        Remove-Item -Path $file.FullName -Force
        Write-Verbose "Cleaned up: $($file.FullName)"
        $cleanedFiles += $file.FullName
    }
    catch {
        Write-Warning "Failed to delete $($file.FullName): $($_.Exception.Message)"
    }
}

$cleanedSizeMB = [math]::Round(($filesToDelete | Where-Object { $_.FullName -in $cleanedFiles } | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
Write-Host "Cleaned up $($cleanedFiles.Count) file(s), freed $cleanedSizeMB MB"

return $cleanedFiles
