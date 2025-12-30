#Requires -RunAsAdministrator
# Account_AuthProvider_Windows_New.ps1
# Creates a new Windows-authenticated user account (local Windows user + database entry)

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$UserName,

    [Parameter(Mandatory=$false)]
    [string]$Password,

    [Parameter(Mandatory=$false)]
    [string]$Email,

    [switch]$TestAccount
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

# Generate test account credentials if TestAccount switch is used
if ($TestAccount) {
    $randomLetters = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
    $UserName = "TA_Windows_$randomLetters"
    $Email = "$UserName@$env:COMPUTERNAME"

    # Generate secure random password that meets Windows requirements
    # Windows requires: 3 of 4 categories (upper, lower, digit, special)
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $numbers = '23456789'
    $symbols = '!@#$%^&*'

    # Ensure minimum requirements are met
    $passwordChars = @()
    $passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
    $passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
    $passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
    $passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
    $passwordChars += $numbers[(Get-Random -Maximum $numbers.Length)]
    $passwordChars += $numbers[(Get-Random -Maximum $numbers.Length)]
    $passwordChars += $symbols[(Get-Random -Maximum $symbols.Length)]
    $passwordChars += $symbols[(Get-Random -Maximum $symbols.Length)]

    # Add 8 more random characters
    $allChars = $upper + $lower + $numbers + $symbols
    $passwordChars += (1..8) | ForEach-Object { $allChars[(Get-Random -Maximum $allChars.Length)] }

    # Shuffle the characters
    $Password = -join ($passwordChars | Get-Random -Count $passwordChars.Length)

    Write-Verbose "Generated test account credentials:"
    Write-Verbose "  UserName: $UserName"
    Write-Verbose "  Email: $Email"
    Write-Verbose "  Password: $Password"
}

# Validate required parameters
if ([string]::IsNullOrEmpty($UserName)) {
    throw "UserName parameter is required when not using -TestAccount switch"
}
if ([string]::IsNullOrEmpty($Password)) {
    throw "Password parameter is required when not using -TestAccount switch"
}
if ([string]::IsNullOrEmpty($Email)) {
    $Email = "$UserName@$env:COMPUTERNAME"
}

# Check if local Windows user already exists
$existingLocalUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if ($existingLocalUser) {
    throw "Local Windows user '$UserName' already exists"
}

# Check if database user already exists
$existingDbUser = Get-PSWebHostUser -Email $Email
if ($existingDbUser) {
    throw "Database user with email '$Email' already exists (UserID: $($existingDbUser.UserID))"
}

# Create local Windows user
Write-Verbose "Creating local Windows user: $UserName"
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$newLocalUser = New-LocalUser -Name $UserName -Password $securePassword -PasswordNeverExpires -Description "PsWebHost test account"

if (-not $newLocalUser) {
    throw "Failed to create local Windows user"
}

Write-Verbose "Local Windows user created: $UserName"

try {
    # Create database user entry
    Write-Verbose "Creating database user account for: $Email"
    $user = Register-PSWebHostUser -UserName $UserName -Email $Email -Provider "Windows" -Verbose:$VerbosePreference

    if ($user) {
        Write-Verbose "Database user created successfully with UserID: $($user.UserID)"

        # Return account details as object
        [PSCustomObject]@{
            UserID = $user.UserID
            Email = $user.Email
            UserName = $UserName
            Password = $Password
            LocalUserSID = $newLocalUser.SID.Value
            Created = Get-Date
            IsTestAccount = $TestAccount
        }
    }
    else {
        throw "Failed to create database user account"
    }
}
catch {
    # Rollback: Remove the local user if database creation failed
    Write-Warning "Database user creation failed. Removing local Windows user..."
    Remove-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    throw
}
