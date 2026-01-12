# UserProviders_Get.ps1
# Retrieves user-provider relationships from the database

[CmdletBinding(DefaultParameterSetName='ByUser')]
param(
    [Parameter(ParameterSetName='ByUser')]
    [string]$UserID,

    [Parameter(ParameterSetName='ByEmail')]
    [string]$Email,

    [Parameter(ParameterSetName='ByProvider')]
    [string]$Provider,

    [Parameter(ParameterSetName='ListAll')]
    [switch]$ListAll,

    [switch]$IncludeUserDetails
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[UserProviders_Get.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

if ($PSCmdlet.ParameterSetName -eq 'ByUser') {
    if ([string]::IsNullOrEmpty($UserID)) {
        throw "UserID parameter is required for this parameter set"
    }
    $safeUserID = Sanitize-SqlQueryString -String $UserID
    if ($IncludeUserDetails) {
        $query = @"
SELECT ap.*, u.Email, u.PasswordHash
FROM auth_user_provider ap
INNER JOIN Users u ON ap.UserID = u.UserID
WHERE ap.UserID COLLATE NOCASE = '$safeUserID';
"@
    } else {
        $query = "SELECT * FROM auth_user_provider WHERE UserID COLLATE NOCASE = '$safeUserID';"
    }
}
elseif ($PSCmdlet.ParameterSetName -eq 'ByEmail') {
    if ([string]::IsNullOrEmpty($Email)) {
        throw "Email parameter is required for this parameter set"
    }
    $safeEmail = Sanitize-SqlQueryString -String $Email
    $query = @"
SELECT ap.*, u.Email
FROM auth_user_provider ap
INNER JOIN Users u ON ap.UserID = u.UserID
WHERE u.Email COLLATE NOCASE = '$safeEmail';
"@
}
elseif ($PSCmdlet.ParameterSetName -eq 'ByProvider') {
    if ([string]::IsNullOrEmpty($Provider)) {
        throw "Provider parameter is required for this parameter set"
    }
    $safeProvider = Sanitize-SqlQueryString -String $Provider
    if ($IncludeUserDetails) {
        $query = @"
SELECT ap.*, u.Email
FROM auth_user_provider ap
INNER JOIN Users u ON ap.UserID = u.UserID
WHERE ap.provider = '$safeProvider'
ORDER BY ap.created DESC;
"@
    } else {
        $query = "SELECT * FROM auth_user_provider WHERE provider = '$safeProvider' ORDER BY created DESC;"
    }
}
elseif ($ListAll) {
    if ($IncludeUserDetails) {
        $query = @"
SELECT ap.*, u.Email
FROM auth_user_provider ap
INNER JOIN Users u ON ap.UserID = u.UserID
ORDER BY u.Email, ap.provider;
"@
    } else {
        $query = "SELECT * FROM auth_user_provider ORDER BY UserID, provider;"
    }
}
else {
    throw "No valid parameter set specified"
}

Write-Verbose "$MyTag Executing query: $query"
$providers = Get-PSWebSQLiteData -File $dbFile -Query $query

if ($providers) {
    # Convert Unix timestamps to DateTime
    foreach ($provider in $providers) {
        if ($provider.created) {
            try {
                $provider | Add-Member -NotePropertyName CreatedDateTime -NotePropertyValue ([datetime]::FromFileTimeUtc([long]$provider.created * 10000000 + 116444736000000000)) -Force
            } catch {
                $provider | Add-Member -NotePropertyName CreatedDateTime -NotePropertyValue $null -Force
            }
        }
        if ($provider.expires) {
            try {
                $provider | Add-Member -NotePropertyName ExpiresDateTime -NotePropertyValue ([datetime]::FromFileTimeUtc([long]$provider.expires * 10000000 + 116444736000000000)) -Force
            } catch {
                $provider | Add-Member -NotePropertyName ExpiresDateTime -NotePropertyValue $null -Force
            }
        }

        # Parse data JSON if present
        if ($provider.data) {
            try {
                $parsedData = $provider.data | ConvertFrom-Json
                $provider | Add-Member -NotePropertyName ParsedData -NotePropertyValue $parsedData -Force
            } catch {
                Write-Verbose "$MyTag Failed to parse data JSON for UserID: $($provider.UserID), Provider: $($provider.provider)"
            }
        }
    }
}

return $providers
