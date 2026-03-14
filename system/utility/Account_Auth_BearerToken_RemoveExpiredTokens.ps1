# Account_Auth_BearerToken_RemoveExpiredTokens.ps1
# Removes expired Bearer tokens and their associated dedicated user accounts

<#
.SYNOPSIS
    Removes expired Bearer tokens and their associated dedicated user accounts.

.DESCRIPTION
    This script should be run periodically (e.g., as a scheduled job) to:
    - Delete API keys that have passed their ExpiresAt date
    - Delete the dedicated user accounts associated with those keys
    - Clean up role assignments for those accounts
    - Optionally generate a report of removed tokens

.PARAMETER DryRun
    If specified, only report what would be deleted without actually deleting.

.PARAMETER Verbose
    If specified, output detailed logging.

.EXAMPLE
    .\Account_Auth_BearerToken_RemoveExpiredTokens.ps1

    Removes all expired tokens and their accounts.

.EXAMPLE
    .\Account_Auth_BearerToken_RemoveExpiredTokens.ps1 -DryRun

    Shows what would be removed without actually removing anything.
#>

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -InitializeEnvironmentOnly 3>$null 4>$null | Out-Null

$MyTag = '[Account_Auth_BearerToken_RemoveExpiredTokens]'
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

Write-Host "`n$MyTag Starting expired token cleanup" -ForegroundColor Cyan
Write-Host "Database: $dbFile" -ForegroundColor Gray

$now = Get-Date
$nowUtc = $now.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')

Write-Host "Current time (UTC): $nowUtc" -ForegroundColor Gray
if ($DryRun) {
    Write-Host "** DRY RUN MODE - No changes will be made **" -ForegroundColor Yellow
}
Write-Host ""

# Step 1: Find expired API keys
$expiredKeysQuery = @"
SELECT k.KeyID, k.Name, k.UserID, k.ExpiresAt, k.CreatedAt, u.Email as DedicatedEmail
FROM API_Keys k
LEFT JOIN Users u ON k.UserID = u.UserID
WHERE k.ExpiresAt IS NOT NULL
  AND k.ExpiresAt < datetime('$nowUtc')
"@

$expiredKeys = Get-PSWebSQLiteData -File $dbFile -Query $expiredKeysQuery

if (-not $expiredKeys -or $expiredKeys.Count -eq 0) {
    Write-Host "$MyTag No expired tokens found." -ForegroundColor Green
    Write-Host ""
    return @{
        Status = 'Success'
        ExpiredKeysFound = 0
        RemovedKeys = @()
        Timestamp = $now
    }
}

$expiredCount = @($expiredKeys).Count
Write-Host "$MyTag Found $expiredCount expired token(s)" -ForegroundColor Yellow
Write-Host ""

$removedKeys = @()

foreach ($key in $expiredKeys) {
    Write-Host "Processing expired key:" -ForegroundColor White
    Write-Host "  KeyID:      $($key.KeyID)" -ForegroundColor Gray
    Write-Host "  Name:       $($key.Name)" -ForegroundColor Gray
    Write-Host "  UserID:     $($key.UserID)" -ForegroundColor Gray
    Write-Host "  Email:      $($key.DedicatedEmail)" -ForegroundColor Gray
    Write-Host "  ExpiresAt:  $($key.ExpiresAt)" -ForegroundColor Gray
    Write-Host "  CreatedAt:  $($key.CreatedAt)" -ForegroundColor Gray

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would delete this key and account" -ForegroundColor Yellow
    } else {
        try {
            $safeKeyID = Sanitize-SqlQueryString -String $key.KeyID
            $safeUserID = Sanitize-SqlQueryString -String $key.UserID

            # Step 2a: Delete role assignments for the dedicated account
            $deleteRolesQuery = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safeUserID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteRolesQuery
            Write-Host "  ✓ Deleted role assignments" -ForegroundColor Green

            # Step 2b: Delete sessions for the dedicated account
            $deleteSessionsQuery = "DELETE FROM Sessions WHERE UserID = '$safeUserID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteSessionsQuery
            Write-Host "  ✓ Deleted sessions" -ForegroundColor Green

            # Step 2c: Delete the API key record
            $deleteKeyQuery = "DELETE FROM API_Keys WHERE KeyID = '$safeKeyID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteKeyQuery
            Write-Host "  ✓ Deleted API key record" -ForegroundColor Green

            # Step 2d: Delete the dedicated user account
            $deleteUserQuery = "DELETE FROM Users WHERE UserID = '$safeUserID';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $deleteUserQuery
            Write-Host "  ✓ Deleted dedicated user account" -ForegroundColor Green

            $removedKeys += [PSCustomObject]@{
                KeyID = $key.KeyID
                Name = $key.Name
                UserID = $key.UserID
                Email = $key.DedicatedEmail
                ExpiresAt = $key.ExpiresAt
                RemovedAt = Get-Date
            }

            Write-Host "  [REMOVED]" -ForegroundColor Green
        }
        catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "DRY RUN SUMMARY" -ForegroundColor Yellow
    Write-Host "Would remove: $expiredCount expired token(s)" -ForegroundColor Yellow
} else {
    Write-Host "CLEANUP SUMMARY" -ForegroundColor Cyan
    Write-Host "Removed: $($removedKeys.Count) expired token(s)" -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Return summary object
[PSCustomObject]@{
    Status = 'Success'
    DryRun = $DryRun
    ExpiredKeysFound = $expiredCount
    RemovedKeys = $removedKeys
    Timestamp = $now
}
