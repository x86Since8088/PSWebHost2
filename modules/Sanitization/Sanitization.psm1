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
        return [System.Web.HttpUtility]::HtmlEncode($InputString)
    }
}

# Function to log request sanitization failures
function Write-RequestSanitizationFail {
    param (
        [string]$Path,
        [string]$Message,
        $Context
    )
    Write-Host -ForegroundColor Blue ("Message: $Message`n`tPath: $Path" +
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
        [Parameter(Mandatory=$true)]
        [string]$BaseDirectory
    )

    if ([string]::IsNullOrEmpty($FilePath)) {
        # Empty file path -> return the base directory normalized
        return @{Score='pass'; Path = [System.IO.Path]::GetFullPath($BaseDirectory)}
    }

    # Check for obvious path traversal sequences like '..'
    if ($FilePath -match '([\\/])\.\.' -or $FilePath.StartsWith('..', [System.StringComparison]::Ordinal)) {
        Write-RequestSanitizationFail -Path $FilePath -Message "Failed check for obvious path traversal sequences, Authorized: $isAuthorized, UserRoles: $($session.Roles -join ', ')" 
        return @{Score='fail'; Message = "Path traversal attempt detected: $FilePath"}
    }

    $fullBaseDirectory = [System.IO.Path]::GetFullPath($BaseDirectory)

    # Join with base
    $combinedPath = Join-Path $fullBaseDirectory $FilePath
    $fullResolvedPath = [System.IO.Path]::GetFullPath($combinedPath)

    # Final check to ensure the resolved path is still within the base directory
    if (-not $fullResolvedPath.StartsWith($fullBaseDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-RequestSanitizationFail -Path $FilePath -Message "Failed check for path traversal attempt detected after resolution, `n`tAuthorized: $isAuthorized, `n`tUserRoles: $($session.Roles -join ', ')`n`tfullResolvedPath: $($fullResolvedPath)`n`tStarts With fullBaseDirectory: $fullBaseDirectory"
        return @{Score='fail'; Message = "Path traversal attempt detected after resolution: $FilePath"}
    }

    return @{Score='pass'; Path = $fullResolvedPath}
}
