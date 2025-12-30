# Create-WindowsUser.ps1
# Creates a Windows authenticated user in the database

[CmdletBinding()]
param(
    [string]$Email = "test@W11",
    [string]$UserName = "test"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Windows User Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Load WebHost environment
Write-Host "[1/2] Loading WebHost environment..." -ForegroundColor Yellow
. (Join-Path $PSScriptRoot '..\WebHost.ps1') -ShowVariables
Write-Host "      ✓ Environment loaded" -ForegroundColor Green

# Check if user already exists
Write-Host "`n[2/2] Checking if user exists..." -ForegroundColor Yellow
$existingUser = Get-PSWebHostUser -Email $Email

if ($existingUser) {
    Write-Host "      ! User '$Email' already exists" -ForegroundColor Yellow
    Write-Host "        UserID: $($existingUser.UserID)" -ForegroundColor Gray
    Write-Host "`n✓ Using existing user" -ForegroundColor Green
} else {
    # Create new Windows user
    Write-Host "`n[2/2] Creating Windows user..." -ForegroundColor Yellow
    try {
        Register-PSWebHostUser -UserName $UserName -Email $Email -Provider "Windows" -Verbose
        Write-Host "      ✓ User created successfully" -ForegroundColor Green
    } catch {
        Write-Host "`n✗ Error creating user:" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✓ Windows User Setup Complete" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
