# UserProviders_Remove.ps1
# Removes a user-provider relationship (and optionally the user if it's their last provider)

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)]
    [string]$UserID,

    [Parameter(Mandatory=$true)]
    [string]$Provider,

    [switch]$RemoveUserIfLastProvider,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[UserProviders_Remove.ps1]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Verify user-provider exists
$safeUserID = Sanitize-SqlQueryString -String $UserID
$safeProvider = Sanitize-SqlQueryString -String $Provider

$user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM Users WHERE UserID = '$safeUserID';"
if (-not $user) {
    throw "User with UserID '$UserID' not found"
}

$providerRecord = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM auth_user_provider WHERE UserID = '$safeUserID' AND provider = '$safeProvider';"
if (-not $providerRecord) {
    throw "Provider '$Provider' not found for user '$($user.Email)'"
}

# Count how many providers this user has
$countQuery = "SELECT COUNT(*) as Count FROM auth_user_provider WHERE UserID = '$safeUserID';"
$providerCount = (Get-PSWebSQLiteData -File $dbFile -Query $countQuery).Count

if ($Force) {
    $ConfirmPreference = 'None'
}

$action = "Remove provider '$Provider' from user '$($user.Email)'"
if ($providerCount -eq 1 -and $RemoveUserIfLastProvider) {
    $action += " (This will also DELETE the user account as it's the last provider)"
}

if ($PSCmdlet.ShouldProcess($action, "User-Provider Relationship", "Remove")) {

    # Remove the provider relationship
    $deleteProviderQuery = "DELETE FROM auth_user_provider WHERE UserID = '$safeUserID' AND provider = '$safeProvider';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteProviderQuery
    Write-Verbose "$MyTag Removed provider '$Provider' from user '$($user.Email)'"

    # If this was the last provider and RemoveUserIfLastProvider is set, delete the user
    if ($providerCount -eq 1 -and $RemoveUserIfLastProvider) {
        Write-Warning "Removing user account '$($user.Email)' as it has no remaining authentication providers"

        # Remove user sessions
        $deleteSessionsQuery = "DELETE FROM LoginSessions WHERE UserID = '$safeUserID';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteSessionsQuery

        # Remove user-group mappings
        $deleteGroupMappingsQuery = "DELETE FROM User_Groups_Map WHERE UserID = '$safeUserID';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteGroupMappingsQuery

        # Remove user roles
        $deleteRolesQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safeUserID' AND PrincipalType = 'User';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteRolesQuery

        # Remove user data
        $deleteDataQuery = "DELETE FROM User_Data WHERE ID = '$safeUserID';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteDataQuery

        # Remove the user
        $deleteUserQuery = "DELETE FROM Users WHERE UserID = '$safeUserID';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteUserQuery

        Write-Host "User '$($user.Email)' removed completely" -ForegroundColor Yellow
    } else {
        Write-Host "Provider '$Provider' removed from user '$($user.Email)'" -ForegroundColor Green
        Write-Verbose "$MyTag User still has $($providerCount - 1) provider(s) remaining"
    }
}
