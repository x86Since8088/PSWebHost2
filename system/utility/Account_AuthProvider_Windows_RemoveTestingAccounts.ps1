#Requires -RunAsAdministrator
# Account_AuthProvider_Windows_RemoveTestingAccounts.ps1
# Removes test accounts (accounts with UserName starting with TA_Windows_)

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Force,
    [switch]$SelectWithGridView,
    [switch]$KeepLocalUsers
)

$ErrorActionPreference = 'Stop'

# Get all test accounts
$getAccountScript = Join-Path $PSScriptRoot "Account_AuthProvider_Windows_Get.ps1"
Write-Verbose "Retrieving test accounts..."
$testAccounts = & $getAccountScript -TestAccountsOnly

if (-not $testAccounts) {
    Write-Host "No test accounts found" -ForegroundColor Yellow
    return
}

# Convert to array if single result
$testAccounts = @($testAccounts)

Write-Host "`nFound $($testAccounts.Count) test account(s):" -ForegroundColor Cyan
$testAccounts | Format-Table UserID, Email, UserName, LocalUserExists, ProviderCreatedDate -AutoSize

# Determine which accounts to delete
$accountsToDelete = @()

if ($SelectWithGridView) {
    Write-Host "`nOpening GridView for selection..." -ForegroundColor Yellow
    $accountsToDelete = $testAccounts | Out-GridView -Title "Select test accounts to delete" -OutputMode Multiple

    if (-not $accountsToDelete) {
        Write-Host "No accounts selected for deletion" -ForegroundColor Yellow
        return
    }
}
elseif ($Force) {
    # Delete all without confirmation
    $accountsToDelete = $testAccounts
    Write-Host "`nDeleting all test accounts (Force mode)..." -ForegroundColor Yellow
}
else {
    # List only, no deletion
    Write-Host "`nTo delete these accounts, use one of the following:" -ForegroundColor Yellow
    Write-Host "  -Force                  : Delete all without confirmation" -ForegroundColor Gray
    Write-Host "  -SelectWithGridView     : Select accounts interactively" -ForegroundColor Gray
    Write-Host "`nAdditional options:" -ForegroundColor Yellow
    Write-Host "  -KeepLocalUsers         : Keep local Windows users, only remove database entries" -ForegroundColor Gray
    return
}

# Delete selected accounts
$removeAccountScript = Join-Path $PSScriptRoot "Account_AuthProvider_Windows_Remove.ps1"
$deletedCount = 0
$failedCount = 0

foreach ($account in $accountsToDelete) {
    try {
        Write-Host "`nDeleting: $($account.Email) ($($account.UserName))..." -ForegroundColor Yellow

        $removeParams = @{
            ID = $account.UserID
        }

        if ($Force) {
            $removeParams.Force = $true
            $removeParams.Confirm = $false
        }

        if ($KeepLocalUsers) {
            $removeParams.KeepLocalUser = $true
        }

        & $removeAccountScript @removeParams

        $deletedCount++
    }
    catch {
        Write-Host "  Failed to delete $($account.Email): $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Deletion Summary:" -ForegroundColor Cyan
Write-Host "  Deleted: $deletedCount" -ForegroundColor $(if ($deletedCount -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Failed:  $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "========================================`n" -ForegroundColor Cyan
