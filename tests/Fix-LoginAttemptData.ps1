# Fix-LoginAttemptData.ps1
# Cleans up invalid datetime values in LastLoginAttempt table

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Fix Login Attempt Data" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Load WebHost environment
Write-Host "[1/2] Loading WebHost environment..." -ForegroundColor Yellow
. (Join-Path $PSScriptRoot '..\WebHost.ps1') -ShowVariables
Write-Host "      ✓ Environment loaded" -ForegroundColor Green

# Fix invalid datetime values
Write-Host "`n[2/2] Fixing invalid datetime values..." -ForegroundColor Yellow
$dbFile = 'C:\sc\PsWebHost\PsWebHost_Data\pswebhost.db'

# Query to find records with invalid lockout dates
$checkQuery = "SELECT * FROM LastLoginAttempt WHERE UserNameLockedUntil = '-62135575200' OR IPAddressLockedUntil = '-62135575200';"
$invalidRecords = Get-PSWebSQLiteData -File $dbFile -Query $checkQuery

if ($invalidRecords) {
    Write-Host "      Found $(@($invalidRecords).Count) record(s) with invalid lockout dates" -ForegroundColor Yellow

    # Update all invalid records to NULL
    $fixQuery = "UPDATE LastLoginAttempt SET UserNameLockedUntil = NULL, IPAddressLockedUntil = NULL WHERE UserNameLockedUntil = '-62135575200' OR IPAddressLockedUntil = '-62135575200';"

    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $fixQuery
    Write-Host "      ✓ Fixed invalid lockout dates" -ForegroundColor Green

    # Verify fix
    $verifyQuery = "SELECT * FROM LastLoginAttempt;"
    $allRecords = Get-PSWebSQLiteData -File $dbFile -Query $verifyQuery
    Write-Host "`n      After fix:" -ForegroundColor Cyan
    $allRecords | Format-Table -AutoSize
} else {
    Write-Host "      ✓ No invalid records found" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✓ Fix Complete" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
