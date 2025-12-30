# Account_AuthProvider_Password_New.ps1
# Creates a new password-authenticated user account

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Email,

    [Parameter(Mandatory=$false)]
    [string]$UserName,

    [Parameter(Mandatory=$false)]
    [string]$Password,

    [switch]$TestAccount
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment (initializes SQLite and required modules)
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

# Generate test account credentials if TestAccount switch is used
if ($TestAccount) {
    $randomLetters = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
    $Email = "TA_Password_$randomLetters@localhost"
    $UserName = "TA_Password_$randomLetters"

    # Generate secure random password that meets requirements:
    # - Min 8 chars, 2 uppercase, 2 lowercase, 2 numbers, 2 symbols
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
    Write-Verbose "  Email: $Email"
    Write-Verbose "  UserName: $UserName"
    Write-Verbose "  Password: $Password"
}

# Validate required parameters
if ([string]::IsNullOrEmpty($Email)) {
    throw "Email parameter is required when not using -TestAccount switch"
}
if ([string]::IsNullOrEmpty($UserName)) {
    $UserName = $Email -replace '@.*$'
}
if ([string]::IsNullOrEmpty($Password)) {
    throw "Password parameter is required when not using -TestAccount switch"
}

# Validate password meets requirements
$passwordValidation = Test-IsValidPassword -Password $Password
if (-not $passwordValidation.IsValid) {
    throw "Password validation failed: $($passwordValidation.Message)"
}

# Check if user already exists
$existingUser = Get-PSWebHostUser -Email $Email
if ($existingUser) {
    throw "User with email '$Email' already exists (UserID: $($existingUser.UserID))"
}

# Create the user
Write-Verbose "Creating password user account for: $Email"
$user = Register-PSWebHostUser -UserName $UserName -Email $Email -Provider "Password" -Password $Password -Verbose:$VerbosePreference

if ($user) {
    Write-Verbose "User created successfully with UserID: $($user.UserID)"

    # Return account details as object
    [PSCustomObject]@{
        UserID = $user.UserID
        Email = $user.Email
        UserName = $UserName
        Password = $Password
        Created = Get-Date
        IsTestAccount = $TestAccount
    }
}
else {
    throw "Failed to create user account"
}
