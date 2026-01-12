[Reflection.Assembly]::LoadWithPartialName('System.Web') | Out-Null

function Sanitize-HtmlInput {
    param (
        [Parameter(ValueFromPipeline=$true)]
        [string]$InputString
    )
    process {
        if ([string]::IsNullOrEmpty($InputString)) {
            return ""
        }
        # Regex to find and remove ANSI escape codes
        $ansiEscapeRegex = '[\u001B\u009B][[()#;?]*.{0,2}(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]'
        $sanitizedString = $InputString -replace $ansiEscapeRegex, ''

        # Remove dangerous JavaScript protocols and event handlers BEFORE encoding
        # This prevents attacks that survive HTML encoding
        $sanitizedString = $sanitizedString -replace 'javascript:', ''
        $sanitizedString = $sanitizedString -replace 'vbscript:', ''
        $sanitizedString = $sanitizedString -replace 'data:', ''
        $sanitizedString = $sanitizedString -replace '\bon\w+\s*=', ''  # Remove event handlers like onerror=, onload=, etc.

        return [System.Web.HttpUtility]::HtmlEncode($sanitizedString)
    }
}

# Function to log request sanitization failures
function Write-RequestSanitizationFail {
    param (
        [string]$Path,
        [string]$Message,
        $Context
    )
    # Changed to Write-Warning for better logging practices
    Write-Warning ("Message: $Message`n`tPath: $Path" +
        (.{
            if ($Context) {
                "`n`tUrl.AbsolutePath:$($Context.Request.Url.AbsolutePath)`n`t" 
            }
        }) +
        ((Get-PSCallStack | Select-Object Command, Arguments, Location,@{N='Source';E={$_.InvocationInfo.MyCommand.Source}}|Format-List |out-string).trim() -split '\n' -join "`n`t"))
}

function Sanitize-FilePath {
    param (
        [string]$FilePath,
        [string]$BaseDirectory
    )
    if (-not $BaseDirectory) { Write-Error "The -BaseDirectory parameter is required."; return }

    if ([string]::IsNullOrEmpty($FilePath)) {
        # Empty file path -> return the base directory normalized
        return @{Score='pass'; Path = [System.IO.Path]::GetFullPath($BaseDirectory)}
    }

    # Check for UNC paths (\\server\share)
    if ($FilePath -match '^\\\\') {
        Write-RequestSanitizationFail -Path $FilePath -Message "UNC paths are not allowed."
        return @{Score='fail'; Message = "UNC path not allowed: $FilePath"}
    }

    # Check for absolute paths (C:\, /etc/, etc.)
    if ([System.IO.Path]::IsPathRooted($FilePath)) {
        Write-RequestSanitizationFail -Path $FilePath -Message "Absolute paths are not allowed."
        return @{Score='fail'; Message = "Absolute path not allowed: $FilePath"}
    }

    # Check for obvious path traversal sequences like '..'
    if ($FilePath -match '([\\/])\.\.' -or $FilePath.StartsWith('..', [System.StringComparison]::Ordinal)) {
        # Removed undefined variables $isAuthorized and $session.Roles
        Write-RequestSanitizationFail -Path $FilePath -Message "Failed check for obvious path traversal sequences."
        return @{Score='fail'; Message = "Path traversal attempt detected: $FilePath"}
    }

    $fullBaseDirectory = [System.IO.Path]::GetFullPath($BaseDirectory)

    # Join with base
    $combinedPath = Join-Path $fullBaseDirectory $FilePath
    $fullResolvedPath = [System.IO.Path]::GetFullPath($combinedPath)

    # Final check to ensure the resolved path is still within the base directory
    if (-not $fullResolvedPath.StartsWith($fullBaseDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        # Removed undefined variables
        Write-RequestSanitizationFail -Path $FilePath -Message "Failed check for path traversal attempt detected after resolution. `n`tfullResolvedPath: $($fullResolvedPath)`n`tStarts With fullBaseDirectory: $fullBaseDirectory"
        return @{Score='fail'; Message = "Path traversal attempt detected after resolution: $FilePath"}
    }

    return @{Score='pass'; Path = $fullResolvedPath}
}