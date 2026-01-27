# Account_Auth_BearerToken_Get.ps1
# Creates or retrieves bearer tokens (API keys) for user accounts

[CmdletBinding(DefaultParameterSetName='List')]
param(
    # List mode parameters
    [Parameter(ParameterSetName='List')]
    [switch]$ListAll,

    [Parameter(ParameterSetName='List')]
    [switch]$TestTokensOnly,

    [Parameter(ParameterSetName='List')]
    [string]$UserID,

    # Create mode parameters
    [Parameter(ParameterSetName='Create', Mandatory=$true)]
    [switch]$Create,

    [Parameter(ParameterSetName='Create')]
    [string]$Name,

    [Parameter(ParameterSetName='Create')]
    [string]$ExistingUserID,

    [Parameter(ParameterSetName='Create')]
    [string[]]$Roles = @(),

    [Parameter(ParameterSetName='Create')]
    [string[]]$Groups = @(),

    [Parameter(ParameterSetName='Create')]
    [string[]]$AllowedIPs = @(),

    [Parameter(ParameterSetName='Create')]
    [DateTime]$ExpiresAt,

    [Parameter(ParameterSetName='Create')]
    [string]$Description,

    # Test token creation
    [Parameter(ParameterSetName='Create')]
    [switch]$TestToken
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

#region List Mode
if ($PSCmdlet.ParameterSetName -eq 'List') {
    if ($TestTokensOnly) {
        # List only test tokens (tokens with names starting with TA_Token_)
        $query = "SELECT KeyID, Name, UserID, AllowedIPs, CreatedBy, CreatedAt, ExpiresAt, LastUsed, Enabled, Description
                  FROM API_Keys
                  WHERE Name LIKE 'TA_Token_%'
                  ORDER BY CreatedAt DESC;"
    }
    elseif ($UserID) {
        # List tokens for specific user
        $safeUserID = Sanitize-SqlQueryString -String $UserID
        $query = "SELECT KeyID, Name, UserID, AllowedIPs, CreatedBy, CreatedAt, ExpiresAt, LastUsed, Enabled, Description
                  FROM API_Keys
                  WHERE UserID = '$safeUserID'
                  ORDER BY CreatedAt DESC;"
    }
    else {
        # List all tokens
        $query = "SELECT KeyID, Name, UserID, AllowedIPs, CreatedBy, CreatedAt, ExpiresAt, LastUsed, Enabled, Description
                  FROM API_Keys
                  ORDER BY CreatedAt DESC;"
    }

    $tokens = Get-PSWebSQLiteData -File $dbFile -Query $query

    if (-not $tokens) {
        Write-Host "No tokens found" -ForegroundColor Yellow
        return @()
    }

    # Convert to array if single result
    $tokens = @($tokens)

    # Enhance with user email for display
    $enriched = $tokens | ForEach-Object {
        $userQuery = "SELECT Email FROM Users WHERE UserID = '$(Sanitize-SqlQueryString -String $_.UserID)';"
        $userEmail = (Get-PSWebSQLiteData -File $dbFile -Query $userQuery).Email

        [PSCustomObject]@{
            KeyID = $_.KeyID
            Name = $_.Name
            UserID = $_.UserID
            UserEmail = $userEmail
            AllowedIPs = $_.AllowedIPs
            CreatedAt = $_.CreatedAt
            ExpiresAt = $_.ExpiresAt
            LastUsed = $_.LastUsed
            Enabled = $_.Enabled
            Description = $_.Description
            IsTestToken = $_.Name -like 'TA_Token_*'
        }
    }

    return $enriched
}
#endregion

#region Create Mode
if ($PSCmdlet.ParameterSetName -eq 'Create') {
    $createdUser = $null
    $targetUserID = $null

    # Determine user to associate token with
    if ($ExistingUserID) {
        # Use existing user
        $targetUserID = $ExistingUserID

        # Verify user exists
        $userCheck = Get-PSWebHostUser -UserID $targetUserID
        if (-not $userCheck) {
            throw "User not found: $ExistingUserID"
        }

        Write-Verbose "Using existing user: $($userCheck.Email) (ID: $targetUserID)"
    }
    else {
        # Create new test user with specified roles/groups
        Write-Verbose "Creating new test user for token..."

        $testUserScript = Join-Path $PSScriptRoot "Account_New_TestUser.ps1"

        $userParams = @{
            Prefix = "TA_TokenUser"
            Verbose = $VerbosePreference
        }

        if ($Roles.Count -gt 0) {
            $userParams['Roles'] = $Roles
        }

        if ($Groups.Count -gt 0) {
            $userParams['Groups'] = $Groups
        }

        $createdUser = & $testUserScript @userParams
        $targetUserID = $createdUser.UserID

        Write-Verbose "Created test user: $($createdUser.Email) with roles: $($createdUser.Roles -join ', ')"
    }

    # Generate token name
    if ([string]::IsNullOrEmpty($Name)) {
        if ($TestToken) {
            $randomLetters = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
            $Name = "TA_Token_$randomLetters"
        }
        else {
            $Name = "APIKey_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }
    }

    # Create description if not provided
    if ([string]::IsNullOrEmpty($Description)) {
        if ($TestToken) {
            $roleStr = if ($Roles.Count -gt 0) { " with roles: $($Roles -join ', ')" } else { "" }
            $Description = "Test token created $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')$roleStr"
        }
        else {
            $Description = "API token created $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        }
    }

    # Create the API key (bearer token)
    Write-Verbose "Creating API key: $Name for user $targetUserID"

    $keyParams = @{
        Name = $Name
        UserID = $targetUserID
        Description = $Description
        Verbose = $VerbosePreference
    }

    if ($AllowedIPs.Count -gt 0) {
        $keyParams['AllowedIPs'] = $AllowedIPs
    }

    if ($ExpiresAt) {
        $keyParams['ExpiresAt'] = $ExpiresAt
    }

    $apiKey = New-DatabaseApiKey @keyParams

    if (-not $apiKey) {
        throw "Failed to create API key"
    }

    Write-Host "`n✓ Bearer Token Created Successfully!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

    # Display the result
    $result = [PSCustomObject]@{
        BearerToken = $apiKey.ApiKey
        KeyID = $apiKey.KeyID
        Name = $apiKey.Name
        UserID = $apiKey.UserID
        UserEmail = if ($createdUser) { $createdUser.Email } else { (Get-PSWebHostUser -UserID $targetUserID).Email }
        UserPassword = if ($createdUser) { $createdUser.Password } else { 'N/A' }
        Roles = if ($createdUser) { $createdUser.Roles } else { @(Get-PSWebHostRole -UserID $targetUserID | Select-Object -ExpandProperty RoleName) }
        Groups = if ($createdUser) { $createdUser.Groups } else { @() }
        AllowedIPs = $apiKey.AllowedIPs
        ExpiresAt = $apiKey.ExpiresAt
        IsTestToken = $TestToken -or $Name -like 'TA_Token_*'
        CreatedAt = Get-Date
    }

    Write-Host "`nToken Details:" -ForegroundColor Yellow
    Write-Host "  Bearer Token: $($result.BearerToken)" -ForegroundColor Green
    Write-Host "  Key ID: $($result.KeyID)" -ForegroundColor Gray
    Write-Host "  Name: $($result.Name)" -ForegroundColor Gray
    Write-Host "  User Email: $($result.UserEmail)" -ForegroundColor Gray
    if ($createdUser) {
        Write-Host "  User Password: $($result.UserPassword)" -ForegroundColor Gray
    }
    Write-Host "  Roles: $($result.Roles -join ', ')" -ForegroundColor Cyan
    if ($result.Groups.Count -gt 0) {
        Write-Host "  Groups: $($result.Groups -join ', ')" -ForegroundColor Cyan
    }
    if ($result.AllowedIPs.Count -gt 0) {
        Write-Host "  Allowed IPs: $($result.AllowedIPs -join ', ')" -ForegroundColor Gray
    }
    if ($result.ExpiresAt) {
        Write-Host "  Expires: $($result.ExpiresAt)" -ForegroundColor Gray
    }

    Write-Host "`nUsage Example:" -ForegroundColor Yellow
    Write-Host "  curl -H `"Authorization: Bearer $($result.BearerToken)`" http://localhost:8080/api/v1/cli" -ForegroundColor Cyan
    Write-Host "`n  Or in PowerShell:" -ForegroundColor Yellow
    Write-Host "  `$headers = @{ 'Authorization' = 'Bearer $($result.BearerToken)' }" -ForegroundColor Cyan
    Write-Host "  Invoke-WebRequest -Uri 'http://localhost:8080/api/v1/cli' -Headers `$headers" -ForegroundColor Cyan

    Write-Host "`n⚠️  IMPORTANT: Save this token securely - it cannot be retrieved again!" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

    return $result
}
#endregion
