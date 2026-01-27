# Account_Auth_BearerToken_Remove.ps1
# Removes bearer tokens (API keys)

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='ByKeyID')]
    [string]$KeyID,

    [Parameter(Mandatory=$true, ParameterSetName='ByName')]
    [string]$Name,

    [Parameter(ParameterSetName='ByKeyID')]
    [Parameter(ParameterSetName='ByName')]
    [switch]$Force,

    [Parameter(ParameterSetName='ByKeyID')]
    [Parameter(ParameterSetName='ByName')]
    [switch]$RemoveUser
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

# Retrieve token details before deletion
if ($KeyID) {
    $safeKeyID = Sanitize-SqlQueryString -String $KeyID
    $query = "SELECT * FROM API_Keys WHERE KeyID = '$safeKeyID';"
}
elseif ($Name) {
    $safeName = Sanitize-SqlQueryString -String $Name
    $query = "SELECT * FROM API_Keys WHERE Name = '$safeName';"
}

$token = Get-PSWebSQLiteData -File $dbFile -Query $query

if (-not $token) {
    Write-Warning "Token not found: $KeyID$Name"
    return $false
}

# Get user email for display
$userEmail = (Get-PSWebHostUser -UserID $token.UserID).Email

Write-Host "`nToken to be removed:" -ForegroundColor Yellow
Write-Host "  Key ID: $($token.KeyID)" -ForegroundColor Gray
Write-Host "  Name: $($token.Name)" -ForegroundColor Gray
Write-Host "  User: $userEmail ($($token.UserID))" -ForegroundColor Gray
Write-Host "  Created: $($token.CreatedAt)" -ForegroundColor Gray

# Confirm deletion unless Force is specified
if (-not $Force) {
    if (-not $PSCmdlet.ShouldProcess($token.Name, "Remove bearer token")) {
        Write-Host "Operation cancelled" -ForegroundColor Yellow
        return $false
    }
}

# Remove the token
Write-Verbose "Removing token: $($token.Name)"

$removeParams = @{}
if ($KeyID) {
    $removeParams['KeyID'] = $KeyID
}
else {
    $removeParams['Name'] = $Name
}

$removed = Remove-DatabaseApiKey @removeParams

if ($removed) {
    Write-Host "✓ Token removed successfully" -ForegroundColor Green

    # Optionally remove the associated user
    if ($RemoveUser) {
        # Check if this is a test user (TA_TokenUser prefix)
        if ($userEmail -like 'TA_TokenUser*@localhost') {
            Write-Host "`nRemoving associated test user..." -ForegroundColor Yellow

            try {
                # Check if user has other tokens
                $otherTokensQuery = "SELECT COUNT(*) as Count FROM API_Keys WHERE UserID = '$(Sanitize-SqlQueryString -String $token.UserID)';"
                $otherTokensCount = (Get-PSWebSQLiteData -File $dbFile -Query $otherTokensQuery).Count

                if ($otherTokensCount -gt 0) {
                    Write-Warning "User has $otherTokensCount other token(s). Skipping user deletion."
                }
                else {
                    # Remove user
                    $removeUserScript = Join-Path $PSScriptRoot "Account_AuthProvider_Password_Remove.ps1"
                    & $removeUserScript -ID $token.UserID -Force -Confirm:$false

                    Write-Host "✓ Associated user removed" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Failed to remove user: $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "User is not a test user (does not start with TA_TokenUser). Skipping user deletion."
            Write-Host "  To remove manually: Account_AuthProvider_Password_Remove.ps1 -ID $($token.UserID)" -ForegroundColor Gray
        }
    }

    return $true
}
else {
    Write-Host "✗ Failed to remove token" -ForegroundColor Red
    return $false
}
