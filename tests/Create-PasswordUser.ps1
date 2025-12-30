# Create-PasswordUser.ps1
# Creates a password authenticated user in the database

[CmdletBinding()]
param(
    [string]$Email = "test@localhost",
    [string]$UserName = "test",
    [string]$Password = "TestPassword12!@"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Password User Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Load WebHost environment
Write-Host "[1/3] Loading WebHost environment..." -ForegroundColor Yellow
. (Join-Path $PSScriptRoot '..\WebHost.ps1') -ShowVariables
Write-Host "      ✓ Environment loaded" -ForegroundColor Green

# Validate password
Write-Host "`n[2/3] Validating password..." -ForegroundColor Yellow
$passwordValidation = Test-IsValidPassword -Password $Password
if (-not $passwordValidation.IsValid) {
    Write-Host "      ✗ Password validation failed:" -ForegroundColor Red
    Write-Host "        $($passwordValidation.Message)" -ForegroundColor Red
    throw "Password does not meet requirements"
}
Write-Host "      ✓ Password is valid" -ForegroundColor Green

# Check if user already exists
Write-Host "`n[3/3] Checking if user exists..." -ForegroundColor Yellow
$existingUser = Get-PSWebHostUser -Email $Email

if ($existingUser) {
    Write-Host "      ! User '$Email' already exists" -ForegroundColor Yellow
    Write-Host "        UserID: $($existingUser.UserID)" -ForegroundColor Gray
    Write-Host "`n✓ Using existing user" -ForegroundColor Green
} else {
    # Create new Password user
    Write-Host "`n[3/3] Creating Password user..." -ForegroundColor Yellow
    try {
        Register-PSWebHostUser -UserName $UserName -Email $Email -Provider "Password" -Password $Password -Verbose
        Write-Host "      ✓ User created successfully" -ForegroundColor Green
    } catch {
        Write-Host "`n✗ Error creating user:" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✓ Password User Setup Complete" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Login credentials:" -ForegroundColor Cyan
Write-Host "  Email:    $Email" -ForegroundColor White
Write-Host "  Password: $Password" -ForegroundColor White
Write-Host ""
