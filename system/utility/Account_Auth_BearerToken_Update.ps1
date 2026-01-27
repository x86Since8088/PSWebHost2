# Account_Auth_BearerToken_Update.ps1
# Updates Bearer token (API key) properties including roles, owner, and settings

<#
.SYNOPSIS
    Updates properties of an existing Bearer token (API key).

.DESCRIPTION
    Allows updating various properties of API keys including:
    - Roles (assigned to the key's user account via PSWeb_Roles)
    - Owner (User or Group who manages this key's user account)
    - Name and description
    - Expiration date
    - IP restrictions
    - Enabled status

    Note: Each API key has its own user account. Roles are managed via the
    standard RoleAssignment utilities targeting the key's UserID.

.PARAMETER KeyID
    The KeyID of the API key to update.

.PARAMETER Name
    The name of the API key to update (alternative to KeyID).

.PARAMETER NewName
    New name for the API key.

.PARAMETER NewDescription
    New description for the API key.

.PARAMETER SetOwner
    Set the owner of the API key (UserID or GroupID).

.PARAMETER OwnerType
    Type of owner: 'User' or 'Group'.

.PARAMETER AddRoles
    Array of role names to add to this API key's user account.

.PARAMETER RemoveRoles
    Array of role names to remove from this API key's user account.

.PARAMETER SetRoles
    Replace all roles with this array (clears existing roles first).
    Uses RoleAssignment utilities to manage the key's user account roles.

.PARAMETER SetExpiration
    Set new expiration date.

.PARAMETER RemoveExpiration
    Remove expiration date (key never expires).

.PARAMETER AddAllowedIPs
    Add IP addresses to allowed list.

.PARAMETER RemoveAllowedIPs
    Remove IP addresses from allowed list.

.PARAMETER SetAllowedIPs
    Replace allowed IPs with this list.

.PARAMETER Enable
    Enable the API key.

.PARAMETER Disable
    Disable the API key.

.EXAMPLE
    .\Account_Auth_BearerToken_Update.ps1 -KeyID "abc-123" -AddRoles "debug","admin"

    Adds debug and admin roles to the API key.

.EXAMPLE
    .\Account_Auth_BearerToken_Update.ps1 -Name "MyAPIKey" -SetOwner "user@example.com" -OwnerType User

    Sets the owner of the API key to a specific user.

.EXAMPLE
    .\Account_Auth_BearerToken_Update.ps1 -KeyID "abc-123" -SetRoles "read_only"

    Replaces all roles with just read_only role.

.EXAMPLE
    .\Account_Auth_BearerToken_Update.ps1 -Name "TestKey" -Disable

    Disables the API key.
#>

[CmdletBinding()]
param(
    [Parameter(ParameterSetName='ByKeyID', Mandatory=$true)]
    [string]$KeyID,

    [Parameter(ParameterSetName='ByName', Mandatory=$true)]
    [string]$Name,

    [string]$NewName,
    [string]$NewDescription,

    [string]$SetOwner,
    [ValidateSet('User', 'Group')]
    [string]$OwnerType = 'User',

    [string[]]$AddRoles = @(),
    [string[]]$RemoveRoles = @(),
    [string[]]$SetRoles,

    [DateTime]$SetExpiration,
    [switch]$RemoveExpiration,

    [string[]]$AddAllowedIPs = @(),
    [string[]]$RemoveAllowedIPs = @(),
    [string[]]$SetAllowedIPs,

    [switch]$Enable,
    [switch]$Disable
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Account_Auth_BearerToken_Update]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

# Resolve KeyID if Name provided
if ($PSCmdlet.ParameterSetName -eq 'ByName') {
    $safeName = Sanitize-SqlQueryString -String $Name
    $keyLookup = Get-PSWebSQLiteData -File $dbFile -Query "SELECT KeyID FROM API_Keys WHERE Name = '$safeName';"
    if (-not $keyLookup) {
        throw "API key with name '$Name' not found"
    }
    $KeyID = $keyLookup.KeyID
    Write-Verbose "$MyTag Resolved name '$Name' to KeyID '$KeyID'"
}

# Get current key info
$safeKeyID = Sanitize-SqlQueryString -String $KeyID
$currentKey = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM API_Keys WHERE KeyID = '$safeKeyID';"

if (-not $currentKey) {
    throw "API key with KeyID '$KeyID' not found"
}

Write-Host "`nUpdating API Key: $($currentKey.Name)" -ForegroundColor Cyan
Write-Host "KeyID: $KeyID" -ForegroundColor Gray

$updates = @()

# Update basic properties
if ($NewName) {
    $safeNewName = Sanitize-SqlQueryString -String $NewName
    $updates += "Name = '$safeNewName'"
    Write-Host "  → Setting name to: $NewName" -ForegroundColor Yellow
}

if ($NewDescription) {
    $safeNewDesc = Sanitize-SqlQueryString -String $NewDescription
    $updates += "Description = '$safeNewDesc'"
    Write-Host "  → Setting description to: $NewDescription" -ForegroundColor Yellow
}

# Update owner
if ($SetOwner) {
    # Resolve email to UserID if needed
    if ($OwnerType -eq 'User' -and $SetOwner -like '*@*') {
        $safeEmail = Sanitize-SqlQueryString -String $SetOwner
        $user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID FROM Users WHERE Email COLLATE NOCASE = '$safeEmail';"
        if ($user) {
            $SetOwner = $user.UserID
            Write-Verbose "$MyTag Resolved email to UserID: $SetOwner"
        }
    }

    $safeOwner = Sanitize-SqlQueryString -String $SetOwner
    $safeOwnerType = Sanitize-SqlQueryString -String $OwnerType
    $updates += "Owner = '$safeOwner', OwnerType = '$safeOwnerType'"
    Write-Host "  → Setting owner to: $SetOwner ($OwnerType)" -ForegroundColor Yellow
}

# Update expiration
if ($SetExpiration) {
    $expiresStr = $SetExpiration.ToString('o')
    $updates += "ExpiresAt = '$expiresStr'"
    Write-Host "  → Setting expiration to: $SetExpiration" -ForegroundColor Yellow
}

if ($RemoveExpiration) {
    $updates += "ExpiresAt = ''"
    Write-Host "  → Removing expiration (key never expires)" -ForegroundColor Yellow
}

# Update allowed IPs
if ($SetAllowedIPs) {
    $safeIPs = Sanitize-SqlQueryString -String ($SetAllowedIPs -join ',')
    $updates += "AllowedIPs = '$safeIPs'"
    Write-Host "  → Setting allowed IPs to: $($SetAllowedIPs -join ', ')" -ForegroundColor Yellow
} elseif ($AddAllowedIPs.Count -gt 0 -or $RemoveAllowedIPs.Count -gt 0) {
    $currentIPs = if ($currentKey.AllowedIPs) { $currentKey.AllowedIPs -split ',' } else { @() }
    $newIPs = [System.Collections.ArrayList]@($currentIPs)

    foreach ($ip in $AddAllowedIPs) {
        if ($ip -notin $newIPs) {
            $newIPs.Add($ip) | Out-Null
            Write-Host "  → Adding allowed IP: $ip" -ForegroundColor Yellow
        }
    }

    foreach ($ip in $RemoveAllowedIPs) {
        if ($ip -in $newIPs) {
            $newIPs.Remove($ip) | Out-Null
            Write-Host "  → Removing allowed IP: $ip" -ForegroundColor Yellow
        }
    }

    $safeIPs = Sanitize-SqlQueryString -String ($newIPs -join ',')
    $updates += "AllowedIPs = '$safeIPs'"
}

# Update enabled status
if ($Enable -and $Disable) {
    throw "Cannot specify both -Enable and -Disable"
}

if ($Enable) {
    $updates += "Enabled = 1"
    Write-Host "  → Enabling API key" -ForegroundColor Yellow
}

if ($Disable) {
    $updates += "Enabled = 0"
    Write-Host "  → Disabling API key" -ForegroundColor Yellow
}

# Apply updates to API_Keys table
if ($updates.Count -gt 0) {
    $updateQuery = "UPDATE API_Keys SET $($updates -join ', ') WHERE KeyID = '$safeKeyID';"
    Write-Verbose "$MyTag Executing: $updateQuery"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $updateQuery
    Write-Host "`n✓ API key properties updated" -ForegroundColor Green
}

# Update roles (on the key's user account) using RoleAssignment utilities
$rolesUpdated = $false
$keyUserID = $finalKey.UserID

$roleNewScript = Join-Path $ProjectRoot "system\utility\RoleAssignment_New.ps1"
$roleRemoveScript = Join-Path $ProjectRoot "system\utility\RoleAssignment_Remove.ps1"
$roleGetScript = Join-Path $ProjectRoot "system\utility\RoleAssignment_Get.ps1"

if ($SetRoles) {
    # Clear existing roles and set new ones
    Write-Host "`n→ Replacing all roles for API key's user account..." -ForegroundColor Yellow

    # Get current roles
    $currentRoles = & $roleGetScript -UserID $keyUserID -Format Simple 2>$null

    # Remove all current roles
    if ($currentRoles) {
        foreach ($currentRole in $currentRoles) {
            & $roleRemoveScript -PrincipalID $keyUserID -PrincipalType User -RoleName $currentRole.RoleName 2>&1 | Out-Null
        }
    }

    # Add new roles
    foreach ($role in $SetRoles) {
        & $roleNewScript -PrincipalID $keyUserID -PrincipalType User -RoleName $role -CreateRoleIfMissing 2>&1 | Out-Null
        Write-Host "  ✓ Added role: $role" -ForegroundColor Green
    }
    $rolesUpdated = $true
}

if ($AddRoles.Count -gt 0) {
    Write-Host "`n→ Adding roles to API key's user account..." -ForegroundColor Yellow
    foreach ($role in $AddRoles) {
        & $roleNewScript -PrincipalID $keyUserID -PrincipalType User -RoleName $role -CreateRoleIfMissing 2>&1 | Out-Null
        Write-Host "  ✓ Added role: $role" -ForegroundColor Green
    }
    $rolesUpdated = $true
}

if ($RemoveRoles.Count -gt 0) {
    Write-Host "`n→ Removing roles from API key's user account..." -ForegroundColor Yellow
    foreach ($role in $RemoveRoles) {
        & $roleRemoveScript -PrincipalID $keyUserID -PrincipalType User -RoleName $role 2>&1 | Out-Null
        Write-Host "  ✓ Removed role: $role" -ForegroundColor Green
    }
    $rolesUpdated = $true
}

if ($rolesUpdated) {
    Write-Host "`n✓ API key roles updated (via user account $keyUserID)" -ForegroundColor Green
}

# Show final state
Write-Host "`n" -NoNewline
$finalKey = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM API_Keys WHERE KeyID = '$safeKeyID';"

# Get user account info
$keyUser = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email, Owner, OwnerType FROM Users WHERE UserID = '$($finalKey.UserID)';"

# Get roles via RoleAssignment_Get
$finalRoles = & $roleGetScript -UserID $finalKey.UserID -Format Simple 2>$null

# Get owner info
$ownerInfo = "Unknown"
if ($keyUser.Owner) {
    if ($keyUser.OwnerType -eq 'User') {
        $ownerUser = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email FROM Users WHERE UserID = '$($keyUser.Owner)';"
        $ownerInfo = if ($ownerUser) { "$($ownerUser.Email) (User)" } else { "$($keyUser.Owner) (User)" }
    } else {
        $ownerGroup = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Name FROM User_Groups WHERE GroupID = '$($keyUser.Owner)';"
        $ownerInfo = if ($ownerGroup) { "$($ownerGroup.Name) (Group)" } else { "$($keyUser.Owner) (Group)" }
    }
}

Write-Host "Current API Key State:" -ForegroundColor Cyan
Write-Host "  Name: $($finalKey.Name)" -ForegroundColor White
Write-Host "  Description: $($finalKey.Description)" -ForegroundColor Gray
Write-Host "  Linked User Account: $($keyUser.Email)" -ForegroundColor Gray
Write-Host "  Owned By: $ownerInfo" -ForegroundColor Gray
Write-Host "  User Roles: $(if ($finalRoles) { ($finalRoles.RoleName -join ', ') } else { 'None' })" -ForegroundColor Cyan
Write-Host "  Enabled: $($finalKey.Enabled -eq 1)" -ForegroundColor $(if ($finalKey.Enabled -eq 1) { 'Green' } else { 'Red' })
if ($finalKey.AllowedIPs) {
    Write-Host "  Allowed IPs: $($finalKey.AllowedIPs)" -ForegroundColor Gray
}
if ($finalKey.ExpiresAt) {
    Write-Host "  Expires: $($finalKey.ExpiresAt)" -ForegroundColor Gray
}

Write-Host ""
