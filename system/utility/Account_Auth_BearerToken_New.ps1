# Account_Auth_BearerToken_New.ps1
# Creates a new Bearer token (API key) with dedicated user account

<#
.SYNOPSIS
    Creates a new Bearer token (API key) with a dedicated user account.

.DESCRIPTION
    Each API key gets its own dedicated user account following the architecture:
    - API Key → Dedicated User Account → Owned by requesting user/group
    - Roles assigned to dedicated account via PSWeb_Roles table
    - Owner field enables vault integration and ownership tracking

.PARAMETER Email
    Email of the requesting user (will be resolved to UserID for Owner field).

.PARAMETER UserID
    UserID of the requesting user (alternative to Email for Owner field).

.PARAMETER Name
    Human-readable name for the API key (required if not using -TestAccount).

.PARAMETER Description
    Description of the API key's purpose.

.PARAMETER Owner
    Owner of the API key (UserID or GroupID). Defaults to requesting user.

.PARAMETER OwnerType
    Type of owner: 'User' or 'Group'. Defaults to 'User'.

.PARAMETER Roles
    Array of role names to assign to the API key's user account.

.PARAMETER AllowedIPs
    Array of allowed IP addresses for IP-based restrictions.

.PARAMETER ExpiresAt
    Optional expiration date/time for the API key.

.PARAMETER TestAccount
    Create a test API key with auto-generated credentials.

.EXAMPLE
    .\Account_Auth_BearerToken_New.ps1 -Email "admin@test.com" -Name "MyAPIKey" -Roles @('debug','api_access')

    Creates an API key owned by admin@test.com with debug and api_access roles.

.EXAMPLE
    .\Account_Auth_BearerToken_New.ps1 -TestAccount -Roles @('debug')

    Creates a test API key with debug role.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$UserID,

    [Parameter(Mandatory=$false)]
    [string]$Email,

    [Parameter(Mandatory=$false)]
    [string]$Name,

    [Parameter(Mandatory=$false)]
    [string]$Description,

    [Parameter(Mandatory=$false)]
    [string[]]$AllowedIPs = @(),

    [Parameter(Mandatory=$false)]
    [DateTime]$ExpiresAt,

    [Parameter(Mandatory=$false)]
    [string]$Owner,

    [Parameter(Mandatory=$false)]
    [ValidateSet('User', 'Group')]
    [string]$OwnerType = 'User',

    [Parameter(Mandatory=$false)]
    [string[]]$Roles = @(),

    [switch]$TestAccount
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$MyTag = '[Account_Auth_BearerToken_New]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
$roleNewScript = Join-Path $ProjectRoot "system\utility\RoleAssignment_New.ps1"

# Generate test account if TestAccount switch is used
if ($TestAccount) {
    $randomLetters = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })

    # Set default name for test account
    if ([string]::IsNullOrEmpty($Name)) {
        $Name = "TestBearerKey_$randomLetters"
    }

    # Set description
    if ([string]::IsNullOrEmpty($Description)) {
        $Description = "Test Bearer token created $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }

    # Set Owner to system for test accounts
    if ([string]::IsNullOrEmpty($Owner)) {
        $Owner = "system"
        $OwnerType = "User"
    }
}

# Resolve Owner from Email/UserID if provided
$ownerUserID = $null
if (-not [string]::IsNullOrEmpty($Email) -or -not [string]::IsNullOrEmpty($UserID)) {
    # Resolve UserID from Email if only Email provided
    if ([string]::IsNullOrEmpty($UserID) -and -not [string]::IsNullOrEmpty($Email)) {
        $user = Get-PSWebHostUser -Email $Email
        if (-not $user) {
            throw "User with email '$Email' not found"
        }
        $UserID = $user.UserID
        Write-Verbose "$MyTag Resolved UserID: $UserID from Email: $Email"
    }

    # Verify requesting user exists
    $requestingUser = Get-PSWebHostUser -UserID $UserID
    if (-not $requestingUser) {
        throw "User with UserID '$UserID' not found"
    }

    # Set Owner to requesting user if not specified
    if ([string]::IsNullOrEmpty($Owner)) {
        $Owner = $UserID
        $OwnerType = "User"
        Write-Verbose "$MyTag Setting owner to requesting user: $($requestingUser.Email)"
    }

    $ownerUserID = $UserID
}

# Validate required parameters
if ([string]::IsNullOrEmpty($Name)) {
    throw "Name parameter is required (or use -TestAccount for auto-generated name)"
}

if ([string]::IsNullOrEmpty($Owner)) {
    $Owner = "system"
    $OwnerType = "User"
    Write-Verbose "$MyTag No owner specified, defaulting to 'system'"
}

# Set default description
if ([string]::IsNullOrEmpty($Description)) {
    if ($ownerUserID) {
        $Description = "Bearer token for $($requestingUser.Email)"
    } else {
        $Description = "Bearer token for $Name"
    }
}

# Step 1: Create dedicated user account for the API key
Write-Host "`nCreating API Key: $Name" -ForegroundColor Cyan
Write-Verbose "$MyTag Creating dedicated user account for API key"

# Generate unique email for dedicated account
$sanitizedName = $Name -replace '[^a-zA-Z0-9_]', '_'
$randomSuffix = -join ((48..57) + (97..102) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
$dedicatedEmail = "api_key_${sanitizedName}_${randomSuffix}@localhost"
$dedicatedUserName = "api_key_${sanitizedName}_${randomSuffix}"

# Generate secure random password (not used for auth, but required for user creation)
$upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
$lower = 'abcdefghijkmnopqrstuvwxyz'
$numbers = '23456789'
$symbols = '!@#$%^&*'
$passwordChars = @()
$passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
$passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
$passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
$passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
$passwordChars += $numbers[(Get-Random -Maximum $numbers.Length)]
$passwordChars += $numbers[(Get-Random -Maximum $numbers.Length)]
$passwordChars += $symbols[(Get-Random -Maximum $symbols.Length)]
$passwordChars += $symbols[(Get-Random -Maximum $symbols.Length)]
$allChars = $upper + $lower + $numbers + $symbols
$passwordChars += (1..8) | ForEach-Object { $allChars[(Get-Random -Maximum $allChars.Length)] }
$dedicatedPassword = -join ($passwordChars | Get-Random -Count $passwordChars.Length)

# Create dedicated user account
$dedicatedUser = Register-PSWebHostUser -UserName $dedicatedUserName -Email $dedicatedEmail -Provider "Password" -Password $dedicatedPassword -Verbose:$VerbosePreference

if (-not $dedicatedUser) {
    throw "Failed to create dedicated user account for API key"
}

Write-Host "  ✓ Created dedicated user account: $dedicatedEmail" -ForegroundColor Green
$dedicatedUserID = $dedicatedUser.UserID

# Step 2: Set Owner on the dedicated user account
Write-Verbose "$MyTag Setting owner on dedicated account: Owner=$Owner, OwnerType=$OwnerType"

# Resolve Owner to UserID if email provided
$resolvedOwner = $Owner
if ($OwnerType -eq 'User' -and $Owner -like '*@*' -and $Owner -ne 'system') {
    $safeEmail = Sanitize-SqlQueryString -String $Owner
    $ownerUser = Get-PSWebSQLiteData -File $dbFile -Query "SELECT UserID FROM Users WHERE Email COLLATE NOCASE = '$safeEmail';"
    if ($ownerUser) {
        $resolvedOwner = $ownerUser.UserID
        Write-Verbose "$MyTag Resolved owner email '$Owner' to UserID '$resolvedOwner'"
    }
}

$safeOwner = Sanitize-SqlQueryString -String $resolvedOwner
$safeOwnerType = Sanitize-SqlQueryString -String $OwnerType
$safeDedicatedUserID = Sanitize-SqlQueryString -String $dedicatedUserID

$updateOwnerQuery = "UPDATE Users SET Owner = '$safeOwner', OwnerType = '$safeOwnerType' WHERE UserID = '$safeDedicatedUserID';"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $updateOwnerQuery

Write-Host "  ✓ Set owner: $Owner ($OwnerType)" -ForegroundColor Green

# Step 3: Assign roles to dedicated account
if ($Roles.Count -gt 0) {
    Write-Host "  → Assigning roles to API key account..." -ForegroundColor Yellow
    foreach ($role in $Roles) {
        & $roleNewScript -PrincipalID $dedicatedUserID -PrincipalType User -RoleName $role -CreateRoleIfMissing 2>&1 | Out-Null
        Write-Host "    ✓ Added role: $role" -ForegroundColor Green
    }
}

# Step 4: Create the API key record
Write-Verbose "$MyTag Creating API key record"
Write-Verbose "  Name: $Name"
Write-Verbose "  Description: $Description"
if ($AllowedIPs.Count -gt 0) {
    Write-Verbose "  Allowed IPs: $($AllowedIPs -join ', ')"
}
if ($ExpiresAt) {
    Write-Verbose "  Expires: $($ExpiresAt.ToString('yyyy-MM-dd HH:mm:ss'))"
}

$apiKeyParams = @{
    Name = $Name
    UserID = $dedicatedUserID
    Description = $Description
    CreatedBy = if ($ownerUserID) { $ownerUserID } else { "system" }
}

if ($AllowedIPs.Count -gt 0) {
    $apiKeyParams['AllowedIPs'] = $AllowedIPs
}

if ($ExpiresAt) {
    $apiKeyParams['ExpiresAt'] = $ExpiresAt
}

$apiKey = New-DatabaseApiKey @apiKeyParams

if (-not $apiKey) {
    throw "Failed to create Bearer token"
}

# Step 5: Update API_Keys record with Owner info
$safeKeyID = Sanitize-SqlQueryString -String $apiKey.KeyID
$updateKeyOwnerQuery = "UPDATE API_Keys SET Owner = '$safeOwner', OwnerType = '$safeOwnerType' WHERE KeyID = '$safeKeyID';"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $updateKeyOwnerQuery

Write-Host "`n✓ Bearer Token Created Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "KeyID:              " -NoNewline -ForegroundColor Yellow
Write-Host $apiKey.KeyID
Write-Host "Name:               " -NoNewline -ForegroundColor Yellow
Write-Host $apiKey.Name
Write-Host "Dedicated Account:  " -NoNewline -ForegroundColor Yellow
Write-Host $dedicatedEmail
Write-Host "Owner:              " -NoNewline -ForegroundColor Yellow
Write-Host "$Owner ($OwnerType)"
if ($Roles.Count -gt 0) {
    Write-Host "Roles:              " -NoNewline -ForegroundColor Yellow
    Write-Host ($Roles -join ', ')
}
Write-Host "API Key:            " -NoNewline -ForegroundColor Yellow
Write-Host $apiKey.ApiKey -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

if ($AllowedIPs.Count -gt 0) {
    Write-Host "Allowed IPs:        $($AllowedIPs -join ', ')" -ForegroundColor Gray
} else {
    Write-Host "Allowed IPs:        All (no restrictions)" -ForegroundColor Gray
}

if ($ExpiresAt) {
    Write-Host "Expires:            $($ExpiresAt.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
} else {
    Write-Host "Expires:            Never" -ForegroundColor Gray
}

Write-Host "`n⚠ IMPORTANT: Save this API key now - it cannot be retrieved later!" -ForegroundColor Red

Write-Host "`nUsage Examples:" -ForegroundColor Cyan
Write-Host "  PowerShell:" -ForegroundColor Yellow
Write-Host "    `$headers = @{ 'Authorization' = 'Bearer $($apiKey.ApiKey)' }" -ForegroundColor White
Write-Host "    Invoke-RestMethod -Uri 'http://localhost:8080/api/endpoint' -Headers `$headers" -ForegroundColor White

Write-Host "`n  curl:" -ForegroundColor Yellow
Write-Host "    curl -H 'Authorization: Bearer $($apiKey.ApiKey)' http://localhost:8080/api/endpoint" -ForegroundColor White

Write-Host "`n  Environment Variable:" -ForegroundColor Yellow
Write-Host "    `$env:API_KEY = '$($apiKey.ApiKey)'" -ForegroundColor White
Write-Host "    curl -H 'Authorization: Bearer `$env:API_KEY' http://localhost:8080/api/endpoint" -ForegroundColor White
Write-Host ""

# Return account details as object
[PSCustomObject]@{
    KeyID = $apiKey.KeyID
    Name = $apiKey.Name
    DedicatedUserID = $dedicatedUserID
    DedicatedEmail = $dedicatedEmail
    Owner = $Owner
    OwnerType = $OwnerType
    Roles = $Roles
    ApiKey = $apiKey.ApiKey
    AllowedIPs = $AllowedIPs
    ExpiresAt = $ExpiresAt
    Created = Get-Date
    IsTestAccount = $TestAccount
}
