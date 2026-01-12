#Requires -RunAsAdministrator
# Account_AuthProvider_Windows_Remove.ps1
# Removes a Windows-authenticated user account (local Windows user + database entry)

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)]
    [Alias('UserID')]
    [string]$ID,

    [switch]$Force,

    [switch]$KeepLocalUser
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
WHERE u.UserID COLLATE NOCASE = '$safeID' AND ap.provider COLLATE NOCASE = 'Windows';
"@

    $user = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

    if (-not $user) {
        throw "User with ID '$ID' not found or is not a Windows provider account"
    }

    $userEmail = $user.Email
    $userName = $user.UserName

    # Check if local Windows user exists
    $localUser = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue

    # Confirm deletion unless -Force is used
    if ($Force) {
        $confirmed = $true
    }
    elseif ($PSCmdlet.ShouldProcess("User: $userEmail (UserName: $userName, UserID: $ID)", "Delete user account and local Windows user")) {
        $confirmed = $true
    }
    else {
        $confirmed = $false
    }

    if ($confirmed) {
        Write-Verbose "Deleting user account: $userEmail (UserID: $ID)"

        # Delete from auth_user_provider table
        $deleteAuthQuery = "DELETE FROM auth_user_provider WHERE UserID COLLATE NOCASE = '$safeID';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteAuthQuery
        Write-Verbose "Deleted from auth_user_provider table"

        # Delete from Users table
        $deleteUserQuery = "DELETE FROM Users WHERE UserID COLLATE NOCASE = '$safeID';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteUserQuery
        Write-Verbose "Deleted from Users table"

        # Delete from LoginSessions if exists
        $deleteSessionQuery = "DELETE FROM LoginSessions WHERE UserID COLLATE NOCASE = '$safeID';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteSessionQuery
        Write-Verbose "Cleaned up login sessions"

        Write-Host "Successfully deleted database user account: $userEmail" -ForegroundColor Green

        # Remove local Windows user unless KeepLocalUser is specified
        if ($localUser -and -not $KeepLocalUser) {
            try {
                Write-Verbose "Removing local Windows user: $userName"
                Remove-LocalUser -Name $userName -ErrorAction Stop
                Write-Host "Successfully removed local Windows user: $userName" -ForegroundColor Green
                $localUserRemoved = $true
            }
            catch {
                Write-Warning "Failed to remove local Windows user '$userName': $($_.Exception.Message)"
                $localUserRemoved = $false
            }
        }
        else {
            if ($KeepLocalUser) {
                Write-Verbose "Keeping local Windows user as requested: $userName"
            }
            else {
                Write-Verbose "Local Windows user does not exist: $userName"
            }
            $localUserRemoved = $false
        }

        [PSCustomObject]@{
            UserID = $ID
            Email = $userEmail
            UserName = $userName
            DatabaseDeleted = $true
            LocalUserRemoved = $localUserRemoved
            Deleted = Get-Date
        }
    }
    else {
        Write-Warning "User deletion cancelled"
    }
}
