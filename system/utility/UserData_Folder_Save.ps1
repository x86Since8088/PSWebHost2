<#
.SYNOPSIS
    Saves data to a user's application folder.

.DESCRIPTION
    Writes byte data or string content to a file in a user's application folder.
    Structure: [storage location]\[user id]\[application name]\[subfolder]\[filename]

    Security: All paths are validated to prevent directory traversal attacks.

.PARAMETER UserID
    The user ID (required).

.PARAMETER Application
    The application name (required).

.PARAMETER SubFolder
    Optional subfolder path within the application folder.

.PARAMETER Name
    The filename to save (required).

.PARAMETER Bytes
    Byte array to save to the file.

.PARAMETER Content
    String content to save to the file (alternative to -Bytes).

.PARAMETER Encoding
    Text encoding when using -Content. Default is UTF8.

.PARAMETER Force
    Overwrite existing file if it exists.

.EXAMPLE
    .\UserData_Folder_Save.ps1 -UserID "user@example.com" -Application "documents" -Name "report.txt" -Content "Hello World"

.EXAMPLE
    $bytes = [System.IO.File]::ReadAllBytes("C:\temp\file.pdf")
    .\UserData_Folder_Save.ps1 -UserID "admin" -Application "uploads" -SubFolder "2024\Q1" -Name "report.pdf" -Bytes $bytes

.OUTPUTS
    System.IO.FileInfo of the saved file
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
    [string]$Name,

    [Parameter(Mandatory = $false, ParameterSetName = 'Bytes')]
    [byte[]]$Bytes,

    [Parameter(Mandatory = $false, ParameterSetName = 'Content')]
    [string]$Content,

    [Parameter(Mandatory = $false)]
    [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8,

    [switch]$Force
)

# Validate that either Bytes or Content is provided
if (-not $Bytes -and -not $Content) {
    throw "Either -Bytes or -Content must be specified"
}

# Sanitize filename
$Name = $Name -replace '[\\/:*?"<>|]', '_'
if ($Name -match '\.\.') {
    throw "Invalid Name: '..' not allowed"
}

# Get the target folder using UserData_Folder_Get
$getFolderScript = Join-Path $PSScriptRoot "UserData_Folder_Get.ps1"
if (-not (Test-Path $getFolderScript)) {
    throw "UserData_Folder_Get.ps1 not found at: $getFolderScript"
}

$getFolderParams = @{
    UserID = $UserID
    Application = $Application
    CreateIfMissing = $true
}

if ($SubFolder) {
    $getFolderParams.SubFolder = $SubFolder
}

$targetFolder = & $getFolderScript @getFolderParams

if (-not $targetFolder) {
    throw "Failed to get or create target folder"
}

# Build full file path
$filePath = Join-Path $targetFolder.FullName $Name

# Security check: ensure file path is within the target folder
$resolvedFile = [System.IO.Path]::GetFullPath($filePath)
$resolvedFolder = [System.IO.Path]::GetFullPath($targetFolder.FullName)

if (-not $resolvedFile.StartsWith($resolvedFolder, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Security: File path escapes target directory"
}

# Check if file exists
if ((Test-Path $filePath) -and -not $Force) {
    throw "File already exists: $filePath. Use -Force to overwrite."
}

# Save the file
try {
    if ($Bytes) {
        [System.IO.File]::WriteAllBytes($filePath, $Bytes)
    } else {
        [System.IO.File]::WriteAllText($filePath, $Content, $Encoding)
    }

    Write-Verbose "Saved file: $filePath"
    return Get-Item $filePath
}
catch {
    throw "Failed to save file: $($_.Exception.Message)"
}
