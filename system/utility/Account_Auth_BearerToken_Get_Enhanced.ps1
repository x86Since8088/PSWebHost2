# Account_Auth_BearerToken_Get_Enhanced.ps1
# Retrieves Bearer tokens (API keys) with full details including roles and ownership

<#
.SYNOPSIS
    Retrieves Bearer tokens (API keys) with comprehensive details.

.DESCRIPTION
    Lists API keys with full information including:
    - Basic key properties (name, description, expiration)
    - Linked user account details
    - Owner information (who manages this key)
    - Roles (via RoleAssignment_Get.ps1)
    - IP restrictions and enabled status

.PARAMETER KeyID
    Get a specific API key by its KeyID.

.PARAMETER Name
    Get a specific API key by its name.

.PARAMETER UserID
    Get all API keys for a specific user account.

.PARAMETER OwnedBy
    Get all API keys owned by a specific user or group.

.PARAMETER Email
    Get API keys by the linked user's email.

.PARAMETER ListAll
    List all API keys in the system.

.PARAMETER IncludeDisabled
    Include disabled API keys in results (default: only enabled keys).

.PARAMETER Format
    Output format: 'Table', 'List', 'Json', or 'Detailed'. Default is 'Table'.

.EXAMPLE
    .\Account_Auth_BearerToken_Get_Enhanced.ps1 -OwnedBy "admin@test.com"

    Get all API keys owned by admin@test.com.

.EXAMPLE
    .\Account_Auth_BearerToken_Get_Enhanced.ps1 -Name "MyAPIKey" -Format Detailed

    Get detailed information about a specific API key.

.EXAMPLE
    .\Account_Auth_BearerToken_Get_Enhanced.ps1 -ListAll -IncludeDisabled

    List all API keys including disabled ones.
#>

[CmdletBinding(DefaultParameterSetName='List')]
param(
    [Parameter(ParameterSetName='ByKeyID')]
    [string]$KeyID,

    [Parameter(ParameterSetName='ByName')]
    [string]$Name,

    [Parameter(ParameterSetName='ByUserID')]
    [string]$UserID,

    [Parameter(ParameterSetName='ByOwner')]
    [string]$OwnedBy,

    [Parameter(ParameterSetName='ByEmail')]
    [string]$Email,

    [Parameter(ParameterSetName='List')]
    [switch]$ListAll,

    [switch]$IncludeDisabled,

    [ValidateSet('Table', 'List', 'Json', 'Detailed')]
    [string]$Format = 'Table'
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Account_Auth_BearerToken_Get_Enhanced]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
$roleGetScript = Join-Path $ProjectRoot "system\utility\RoleAssignment_Get.ps1"

# Build query based on parameters
$whereClause = @()

if (-not $IncludeDisabled) {
    $whereClause += "ak.Enabled = 1"
}

if ($KeyID) {
    $safeKeyID = Sanitize-SqlQueryString -String $KeyID
    $whereClause += "ak.KeyID = '$safeKeyID'"
}

if ($Name) {
    $safeName = Sanitize-SqlQueryString -String $Name
    $whereClause += "ak.Name = '$safeName'"
}

if ($UserID) {
    $safeUserID = Sanitize-SqlQueryString -String $UserID
    $whereClause += "ak.UserID = '$safeUserID'"
}

if ($Email) {
    $safeEmail = Sanitize-SqlQueryString -String $Email
    $user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID FROM Users WHERE Email COLLATE NOCASE = '$safeEmail';"
    if ($user) {
        $whereClause += "ak.UserID = '$($user.UserID)'"
    } else {
        Write-Warning "No user found with email: $Email"
        return @()
    }
}

if ($OwnedBy) {
    # Resolve OwnedBy to UserID if email provided
    $ownerID = $OwnedBy
    if ($OwnedBy -like '*@*') {
        $safeOwnerEmail = Sanitize-SqlQueryString -String $OwnedBy
        $ownerUser = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID FROM Users WHERE Email COLLATE NOCASE = '$safeOwnerEmail';"
        if ($ownerUser) {
            $ownerID = $ownerUser.UserID
        }
    }
    $safeOwnerID = Sanitize-SqlQueryString -String $ownerID
    $whereClause += "u.Owner = '$safeOwnerID'"
}

$whereSQL = if ($whereClause.Count -gt 0) { "WHERE " + ($whereClause -join ' AND ') } else { "" }

# Query with JOIN to get user info
$query = @"
SELECT
    ak.KeyID,
    ak.Name,
    ak.UserID,
    u.Email as UserEmail,
    u.Owner,
    u.OwnerType,
    ak.AllowedIPs,
    ak.CreatedBy,
    ak.CreatedAt,
    ak.ExpiresAt,
    ak.LastUsed,
    ak.Enabled,
    ak.Description
FROM API_Keys ak
INNER JOIN Users u ON ak.UserID = u.UserID
$whereSQL
ORDER BY ak.CreatedAt DESC;
"@

Write-Verbose "$MyTag Executing query: $query"
$keys = Get-PSWebSQLiteData -File $dbFile -Query $query

if (-not $keys) {
    Write-Host "No API keys found" -ForegroundColor Yellow
    return @()
}

# Convert to array if single result
$keys = @($keys)

# Enhance with roles and owner info
$enriched = $keys | ForEach-Object {
    $key = $_

    # Get roles via RoleAssignment_Get
    $roles = & $roleGetScript -UserID $key.UserID -Format Simple 2>$null
    $roleNames = if ($roles) { $roles.RoleName -join ', ' } else { 'None' }

    # Get owner info
    $ownerInfo = "system"
    if ($key.Owner) {
        if ($key.OwnerType -eq 'User') {
            $ownerUser = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email FROM Users WHERE UserID = '$($key.Owner)';"
            $ownerInfo = if ($ownerUser) { $ownerUser.Email } else { $key.Owner }
        } else {
            $ownerGroup = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Name FROM User_Groups WHERE GroupID = '$($key.Owner)';"
            $ownerInfo = if ($ownerGroup) { $ownerGroup.Name } else { $key.Owner }
        }
    }

    [PSCustomObject]@{
        KeyID = $key.KeyID
        Name = $key.Name
        UserEmail = $key.UserEmail
        Owner = $ownerInfo
        OwnerType = $key.OwnerType
        Roles = $roleNames
        AllowedIPs = $key.AllowedIPs
        CreatedAt = $key.CreatedAt
        ExpiresAt = $key.ExpiresAt
        LastUsed = $key.LastUsed
        Enabled = ($key.Enabled -eq 1)
        Description = $key.Description
    }
}

# Format output
switch ($Format) {
    'Json' {
        return $enriched | ConvertTo-Json -Depth 5
    }
    'List' {
        return $enriched | Format-List
    }
    'Detailed' {
        foreach ($key in $enriched) {
            Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "API Key: $($key.Name)" -ForegroundColor Cyan
            Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  KeyID: $($key.KeyID)" -ForegroundColor Gray
            Write-Host "  Linked User: $($key.UserEmail)" -ForegroundColor White
            Write-Host "  Owned By: $($key.Owner) ($($key.OwnerType))" -ForegroundColor White
            Write-Host "  Roles: $($key.Roles)" -ForegroundColor Cyan
            Write-Host "  Enabled: $($key.Enabled)" -ForegroundColor $(if ($key.Enabled) { 'Green' } else { 'Red' })
            if ($key.AllowedIPs) {
                Write-Host "  Allowed IPs: $($key.AllowedIPs)" -ForegroundColor Gray
            }
            Write-Host "  Created: $($key.CreatedAt)" -ForegroundColor Gray
            if ($key.ExpiresAt) {
                Write-Host "  Expires: $($key.ExpiresAt)" -ForegroundColor Gray
            }
            if ($key.LastUsed) {
                Write-Host "  Last Used: $($key.LastUsed)" -ForegroundColor Gray
            }
            if ($key.Description) {
                Write-Host "  Description: $($key.Description)" -ForegroundColor Gray
            }
        }
        Write-Host ""
        return
    }
    'Table' {
        return $enriched | Format-Table -Property Name, UserEmail, Owner, Roles, Enabled, ExpiresAt -AutoSize
    }
}
