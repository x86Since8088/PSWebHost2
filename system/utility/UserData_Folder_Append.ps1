<#
.SYNOPSIS
    Appends data to a file in a user's application folder.

.DESCRIPTION
    Appends byte data or string content to an existing file (or creates it if it doesn't exist).
    Structure: [storage location]\[user id]\[application name]\[subfolder]\[filename]

    Security: All paths are validated to prevent directory traversal attacks.

.PARAMETER UserID
    The user ID (required).

.PARAMETER Application
    The application name (required).

.PARAMETER SubFolder
    Optional subfolder path within the application folder.

.PARAMETER Name
    The filename to append to (required).

.PARAMETER Bytes
    Byte array to append to the file.

.PARAMETER Content
    String content to append to the file (alternative to -Bytes).

.PARAMETER Encoding
    Text encoding when using -Content. Default is UTF8.

.PARAMETER NewLine
    Add a newline before appending content (only applies to -Content).

.EXAMPLE
    .\UserData_Folder_Append.ps1 -UserID "user@example.com" -Application "logs" -Name "access.log" -Content "User logged in" -NewLine

.EXAMPLE
    $bytes = [byte[]](0x0A, 0x0D)
    .\UserData_Folder_Append.ps1 -UserID "admin" -Application "data" -Name "output.bin" -Bytes $bytes

.OUTPUTS
    System.IO.FileInfo of the file
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

    [Parameter(Mandatory = $false, ParameterSetName = 'Content')]
    [switch]$NewLine
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

# Append to the file
try {
    if ($Bytes) {
        # Append bytes
        $stream = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
        try {
            $stream.Write($Bytes, 0, $Bytes.Length)
        }
        finally {
            $stream.Close()
        }
    } else {
        # Append text
        if ($NewLine -and (Test-Path $filePath)) {
            Add-Content -Path $filePath -Value $Content -Encoding $Encoding.WebName
        } else {
            # No newline, append directly
            $currentContent = if (Test-Path $filePath) {
                [System.IO.File]::ReadAllText($filePath, $Encoding)
            } else {
                ""
            }
            $newContent = $currentContent + $Content
            [System.IO.File]::WriteAllText($filePath, $newContent, $Encoding)
        }
    }

    Write-Verbose "Appended to file: $filePath"
    return Get-Item $filePath
}
catch {
    throw "Failed to append to file: $($_.Exception.Message)"
}
