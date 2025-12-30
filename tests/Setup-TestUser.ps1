# Setup-TestUser.ps1
# Creates a test user in the PsWebHost database for testing authentication

[CmdletBinding()]
param(
    [string]$Email = "test@localhost",
    [string]$Password = "TestPassword123!",
    [string]$AuthProvider = "password"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test User Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Load WebHost environment
Write-Host "[1/3] Loading WebHost environment..." -ForegroundColor Yellow
. (Join-Path $PSScriptRoot '..\WebHost.ps1') -ShowVariables
Write-Host "      ✓ Environment loaded" -ForegroundColor Green

# Check if user already exists
Write-Host "`n[2/3] Checking if user exists..." -ForegroundColor Yellow
$existingUser = Get-PSWebHostUser -Email $Email

if ($existingUser) {
    Write-Host "      ! User '$Email' already exists" -ForegroundColor Yellow
    Write-Host "        UserID: $($existingUser.UserID)" -ForegroundColor Gray
    Write-Host "        Created: $($existingUser.Created)" -ForegroundColor Gray
    Write-Host "`n✓ Using existing user" -ForegroundColor Green
} else {
    # Create new user using built-in function
    Write-Host "`n[3/3] Creating new user..." -ForegroundColor Yellow
    try {
        if ($AuthProvider -eq "password") {
            New-PSWebHostUser -Email $Email -UserName "Test User" -Password $Password
            Write-Host "      ✓ User created successfully" -ForegroundColor Green
        } else {
            Write-Warning "      ! For Windows auth, user must exist in Windows AD/local users"
            Write-Host "        Manual setup required for: $Email" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "`n✗ Error creating user:" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✓ Test User Created Successfully" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Test Credentials:" -ForegroundColor Cyan
Write-Host "  Email:    $Email" -ForegroundColor White
Write-Host "  Password: $Password" -ForegroundColor White
Write-Host "  Provider: $AuthProvider" -ForegroundColor White

Write-Host "`nRun tests with:" -ForegroundColor Yellow
Write-Host "  .\Test-AuthFlow.ps1 -TestUsername '$Email' -TestPassword '$Password'" -ForegroundColor Gray
Write-Host ""
