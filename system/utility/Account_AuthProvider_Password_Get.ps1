# Account_AuthProvider_Password_Get.ps1
# Retrieves password-authenticated user accounts

[CmdletBinding(DefaultParameterSetName='Email')]
param(
    [Parameter(ParameterSetName='Email', Mandatory=$false)]
    [string]$Email,

    [Parameter(ParameterSetName='UserID', Mandatory=$false)]
    [string]$UserID,

    [Parameter(ParameterSetName='ListAll', Mandatory=$false)]
    [switch]$ListAll,

    [Parameter(ParameterSetName='TestAccounts', Mandatory=$false)]
    [switch]$TestAccountsOnly
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

# Build query based on parameters
if ($PSCmdlet.ParameterSetName -eq 'Email') {
    if ($Email) {
        $safeEmail = Sanitize-SqlQueryString -String $Email
        $query = @"
SELECT u.*, ap.UserName, ap.provider, ap.created as ProviderCreated, ap.enabled, ap.locked_out
FROM Users u
INNER JOIN auth_user_provider ap ON u.UserID = ap.UserID
WHERE u.Email = '$safeEmail' AND ap.provider = 'Password';
"@
    }
    else {
        throw "Email parameter is required for this parameter set"
    }
}
elseif ($PSCmdlet.ParameterSetName -eq 'UserID') {
    if ($UserID) {
        $safeUserID = Sanitize-SqlQueryString -String $UserID
        $query = @"
SELECT u.*, ap.UserName, ap.provider, ap.created as ProviderCreated, ap.enabled, ap.locked_out
FROM Users u
INNER JOIN auth_user_provider ap ON u.UserID = ap.UserID
WHERE u.UserID = '$safeUserID' AND ap.provider = 'Password';
"@
    }
    else {
        throw "UserID parameter is required for this parameter set"
    }
}
elseif ($PSCmdlet.ParameterSetName -eq 'TestAccounts') {
    $query = @"
SELECT u.*, ap.UserName, ap.provider, ap.created as ProviderCreated, ap.enabled, ap.locked_out
FROM Users u
INNER JOIN auth_user_provider ap ON u.UserID = ap.UserID
WHERE u.Email LIKE 'TA_Password_%@%' AND ap.provider = 'Password';
"@
}
else {
    # ListAll
    $query = @"
SELECT u.*, ap.UserName, ap.provider, ap.created as ProviderCreated, ap.enabled, ap.locked_out
FROM Users u
INNER JOIN auth_user_provider ap ON u.UserID = ap.UserID
WHERE ap.provider = 'Password';
"@
}

Write-Verbose "Executing query: $query"
$results = Get-PSWebSQLiteData -File $dbFile -Query $query

if ($results) {
    # Convert Unix timestamps to DateTime
    $results | ForEach-Object {
        if ($_.ProviderCreated) {
            $_ | Add-Member -NotePropertyName ProviderCreatedDate -NotePropertyValue ([DateTimeOffset]::FromUnixTimeSeconds($_.ProviderCreated).LocalDateTime) -Force
        }
        $_
    }
}
else {
    Write-Verbose "No password accounts found"
}

return $results
