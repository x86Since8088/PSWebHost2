#Requires -Version 7

<#
.SYNOPSIS
    Creates test API keys for Bearer token authentication in tests

.DESCRIPTION
    This script creates API keys for testing job submission and other APIs.
    Keys are stored in a local test configuration file for reuse.

.PARAMETER UserID
    The UserID to create the API key for (default: auto-generated test user)

.PARAMETER Name
    Name for the API key (default: TestJobSubmissionKey)

.PARAMETER Force
    Force creation of a new key even if one exists

.EXAMPLE
    .\Create-TestApiKey.ps1
    Creates a test API key for a new test user

.EXAMPLE
    .\Create-TestApiKey.ps1 -UserID "existing-user" -Name "MyTestKey"
    Creates a test API key for a specific user

.EXAMPLE
    # From project root
    .\apps\WebHostTaskManagement\tests\twin\Create-TestApiKey.ps1
#>

[CmdletBinding()]
param(
    [string]$UserID,
    [string]$Name = "TestJobSubmissionKey",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Determine project root
if (Test-Path (Join-Path $PSScriptRoot "..\..\..\..\WebHost.ps1")) {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\")).Path
} else {
    # Try to find project root from current directory
    $currentPath = Get-Location
    while ($currentPath -and -not (Test-Path (Join-Path $currentPath "WebHost.ps1"))) {
        $currentPath = Split-Path $currentPath -Parent
    }
    if (-not $currentPath) {
        Write-Error "Cannot find project root (WebHost.ps1). Please run from project directory."
        exit 1
    }
    $projectRoot = $currentPath
}

Write-Verbose "Project root: $projectRoot"

# Load WebHost environment
Write-Host "Loading PSWebHost environment..." -ForegroundColor Cyan
. (Join-Path $projectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

# Path for storing test API keys (relative to script location)
$testConfigDir = Join-Path $PSScriptRoot ".config"
$testConfigFile = Join-Path $testConfigDir "test-api-keys.json"

# Create config directory if needed
if (-not (Test-Path $testConfigDir)) {
    New-Item -Path $testConfigDir -ItemType Directory -Force | Out-Null
}

# Load existing keys
$existingKeys = @{}
if (Test-Path $testConfigFile) {
    try {
        $existingKeys = Get-Content $testConfigFile -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        Write-Warning "Could not load existing config, creating new one"
        $existingKeys = @{}
    }
}

# Check if key already exists
if ($existingKeys.ContainsKey($Name) -and -not $Force) {
    Write-Host "API key '$Name' already exists. Use -Force to recreate." -ForegroundColor Yellow
    Write-Host "Existing key info:" -ForegroundColor Cyan
    $existingKeys[$Name] | ConvertTo-Json -Depth 3
    exit 0
}

# Create test user and API key
if ([string]::IsNullOrEmpty($UserID)) {
    Write-Host "Creating test user and Bearer token..." -ForegroundColor Cyan

    # Generate random test account
    $randomLetters = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
    $testEmail = "TA_JobTest_$randomLetters@localhost"
    $testUserName = "TA_JobTest_$randomLetters"

    # Check if user exists
    $existingUser = Get-PSWebHostUser -Email $testEmail

    if (-not $existingUser) {
        # Generate secure password
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
        $testPassword = -join ($passwordChars | Get-Random -Count $passwordChars.Length)

        # Create test user
        Write-Host "Creating test user: $testEmail" -ForegroundColor Gray
        $newUser = Register-PSWebHostUser -UserName $testUserName -Email $testEmail -Provider "Password" -Password $testPassword

        if (-not $newUser) {
            Write-Error "Failed to create test user"
            exit 1
        }

        $UserID = $newUser.UserID
        Write-Host "  Created user: $($newUser.UserID)" -ForegroundColor Green
    } else {
        $UserID = $existingUser.UserID
        Write-Host "  Using existing user: $($existingUser.UserID)" -ForegroundColor Yellow
    }

    # Add debug role if not present using utility script
    Write-Host "  Checking for 'debug' role..." -ForegroundColor Gray

    # Use the utility script to check existing roles
    $roleAssignScript = Join-Path $projectRoot "system\utility\RoleAssignment_Get.ps1"
    $existingRoles = & $roleAssignScript -UserID $UserID -Format Simple 2>$null

    if ($existingRoles -and ($existingRoles.RoleName -contains 'debug')) {
        Write-Host "  User already has 'debug' role" -ForegroundColor Gray
    } else {
        Write-Host "  Adding 'debug' role..." -ForegroundColor Gray
        $roleNewScript = Join-Path $projectRoot "system\utility\RoleAssignment_New.ps1"
        & $roleNewScript -PrincipalID $UserID -PrincipalType User -RoleName 'debug' -CreateRoleIfMissing | Out-Null
    }
} else {
    # Verify provided UserID exists
    $existingUser = Get-PSWebHostUser -UserID $UserID
    if (-not $existingUser) {
        Write-Error "User with UserID '$UserID' not found"
        exit 1
    }
    Write-Host "Using existing user: $UserID ($($existingUser.Email))" -ForegroundColor Cyan
}

# Create API key
Write-Host "`nCreating API key '$Name'..." -ForegroundColor Cyan

$apiKeyResult = New-DatabaseApiKey `
    -Name $Name `
    -UserID $UserID `
    -Description "Test API key for job submission tests - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
    -CreatedBy "system"

if (-not $apiKeyResult) {
    Write-Error "Failed to create API key"
    exit 1
}

Write-Host "API key created successfully!" -ForegroundColor Green

# Store key info (including the plaintext key for testing)
$existingKeys[$Name] = @{
    KeyID = $apiKeyResult.KeyID
    Name = $apiKeyResult.Name
    UserID = $apiKeyResult.UserID
    ApiKey = $apiKeyResult.ApiKey
    CreatedAt = (Get-Date).ToString('o')
}

# Save to config file
$existingKeys | ConvertTo-Json -Depth 3 | Set-Content $testConfigFile

Write-Host "`nAPI Key Details:" -ForegroundColor Cyan
Write-Host "  KeyID:   $($apiKeyResult.KeyID)" -ForegroundColor White
Write-Host "  Name:    $($apiKeyResult.Name)" -ForegroundColor White
Write-Host "  UserID:  $($apiKeyResult.UserID)" -ForegroundColor White
Write-Host "  ApiKey:  $($apiKeyResult.ApiKey)" -ForegroundColor Yellow

Write-Host "`nIMPORTANT: The API key is stored in:" -ForegroundColor Yellow
Write-Host "  $testConfigFile" -ForegroundColor White

Write-Host "`nTest with curl:" -ForegroundColor Cyan
Write-Host "  curl -H `"Authorization: Bearer $($apiKeyResult.ApiKey)`" http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results" -ForegroundColor White

Write-Host "`nTest with PowerShell:" -ForegroundColor Cyan
Write-Host "  `$apiKey = '$($apiKeyResult.ApiKey)'" -ForegroundColor White
Write-Host "  Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results' -Headers @{ 'Authorization' = 'Bearer `$apiKey' }" -ForegroundColor White
Write-Host ""

# Return the key info
return $apiKeyResult
