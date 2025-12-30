# Account_AuthProvider_Password_Remove.ps1
# Removes a password-authenticated user account

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)]
    [Alias('UserID')]
    [string]$ID,

    [switch]$Force
)

end {
    $ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

# Get user details first
$safeID = Sanitize-SqlQueryString -String $ID
$checkQuery = @"
SELECT u.Email, ap.UserName
FROM Users u
INNER JOIN auth_user_provider ap ON u.UserID = ap.UserID
WHERE u.UserID = '$safeID' AND ap.provider = 'Password';
"@

$user = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if (-not $user) {
    throw "User with ID '$ID' not found or is not a Password provider account"
}

$userEmail = $user.Email
$userName = $user.UserName

# Confirm deletion unless -Force is used
if ($Force) {
    $confirmed = $true
}
elseif ($PSCmdlet.ShouldProcess("User: $userEmail (UserID: $ID)", "Delete user account")) {
    $confirmed = $true
}
else {
    $confirmed = $false
}

if ($confirmed) {
    Write-Verbose "Deleting user account: $userEmail (UserID: $ID)"

    # Delete from auth_user_provider table
    $deleteAuthQuery = "DELETE FROM auth_user_provider WHERE UserID = '$safeID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteAuthQuery
    Write-Verbose "Deleted from auth_user_provider table"

    # Delete from Users table
    $deleteUserQuery = "DELETE FROM Users WHERE UserID = '$safeID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteUserQuery
    Write-Verbose "Deleted from Users table"

    # Delete from LoginSessions if exists
    $deleteSessionQuery = "DELETE FROM LoginSessions WHERE UserID = '$safeID';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteSessionQuery
    Write-Verbose "Cleaned up login sessions"

    Write-Host "Successfully deleted user account: $userEmail" -ForegroundColor Green

    [PSCustomObject]@{
        UserID = $ID
        Email = $userEmail
        UserName = $userName
        Deleted = Get-Date
    }
}
else {
    Write-Warning "User deletion cancelled"
}
}
