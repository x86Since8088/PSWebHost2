#Requires -RunAsAdministrator
# Fix-WindowsAccountComputerName.ps1
# Quick helper to fix Windows auth accounts after computer rename
# Finds accounts with old computer name and updates them to current computer name

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [string]$OldComputerName,

    [Parameter(Mandatory=$false)]
    [string]$UserID,

    [switch]$Force,

    [switch]$UpdateLocalUser
)

$ErrorActionPreference = 'Stop'

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Fix Windows Account After Computer Rename                   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Get current computer name
$currentComputer = $env:COMPUTERNAME
Write-Host "Current computer name: " -NoNewline
Write-Host $currentComputer -ForegroundColor Green

# Get all Windows accounts
Write-Host "`nFetching all Windows authentication accounts..." -ForegroundColor Yellow
$allAccounts = & "$PSScriptRoot\Account_AuthProvider_Windows_Get.ps1" -ListAll

if (-not $allAccounts) {
    Write-Host "No Windows authentication accounts found." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($allAccounts.Count) Windows account(s)" -ForegroundColor Green

# Find accounts that need fixing
$accountsToFix = @()

if ($UserID) {
    # Fix specific account by ID
    $accountsToFix = $allAccounts | Where-Object { $_.UserID -eq $UserID }
    if (-not $accountsToFix) {
        Write-Host "Account with ID '$UserID' not found" -ForegroundColor Red
        exit 1
    }
}
elseif ($OldComputerName) {
    # Find accounts with old computer name
    $accountsToFix = $allAccounts | Where-Object {
        $_.UserName -like "*@$OldComputerName" -or $_.Email -like "*@$OldComputerName"
    }
}
else {
    # Find accounts that don't match current computer name
    $accountsToFix = $allAccounts | Where-Object {
        ($_.UserName -like "*@*" -and $_.UserName -notlike "*@$currentComputer") -or
        ($_.Email -like "*@*" -and $_.Email -notlike "*@$currentComputer")
    }
}

if ($accountsToFix.Count -eq 0) {
    Write-Host "`nNo accounts found that need fixing." -ForegroundColor Green
    Write-Host "All accounts appear to be up-to-date with current computer name." -ForegroundColor Gray
    exit 0
}

# Display accounts that need fixing
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  Accounts Found That Need Fixing                            ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Yellow

$accountsToFix | ForEach-Object {
    Write-Host "User ID    : " -NoNewline; Write-Host $_.UserID -ForegroundColor Cyan
    Write-Host "Email      : " -NoNewline; Write-Host $_.Email -ForegroundColor Yellow
    Write-Host "UserName   : " -NoNewline; Write-Host $_.UserName -ForegroundColor Yellow
    Write-Host "Local Exists: " -NoNewline
    if ($_.LocalUserExists) {
        Write-Host "Yes" -ForegroundColor Green
    } else {
        Write-Host "No" -ForegroundColor Red
    }
    Write-Host "Enabled    : " -NoNewline; Write-Host $_.enabled -ForegroundColor Gray
    Write-Host "LockedOut  : " -NoNewline; Write-Host $_.locked_out -ForegroundColor Gray
    Write-Host ("-" * 60)
}

# Confirm before proceeding
if (-not $Force) {
    Write-Host "`nReady to fix $($accountsToFix.Count) account(s)" -ForegroundColor Cyan
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Fix each account
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  Fixing Accounts                                             ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

$successCount = 0
$failCount = 0
$results = @()

foreach ($account in $accountsToFix) {
    Write-Host "`nProcessing: $($account.Email) (ID: $($account.UserID))" -ForegroundColor Cyan

    try {
        # Parse username to extract local part
        $userNameParts = $account.UserName -split '@'
        if ($userNameParts.Count -eq 2) {
            $localPart = $userNameParts[0]
            $newUserName = "$localPart@$currentComputer"
        } else {
            $newUserName = $account.UserName
        }

        # Parse email to extract local part
        $emailParts = $account.Email -split '@'
        if ($emailParts.Count -eq 2) {
            $emailLocalPart = $emailParts[0]
            $newEmail = "$emailLocalPart@$currentComputer"
        } else {
            $newEmail = $account.Email
        }

        Write-Host "  Old UserName: $($account.UserName)" -ForegroundColor Yellow
        Write-Host "  New UserName: $newUserName" -ForegroundColor Green
        Write-Host "  Old Email   : $($account.Email)" -ForegroundColor Yellow
        Write-Host "  New Email   : $newEmail" -ForegroundColor Green

        # Build parameters for Set script
        $setParams = @{
            ID = $account.UserID
            UserName = $newUserName
            Email = $newEmail
            Force = $true
            Verbose = $VerbosePreference
        }

        if ($UpdateLocalUser) {
            $setParams.UpdateLocalUser = $true
        }

        # Execute update
        $result = & "$PSScriptRoot\Account_AuthProvider_Windows_Set.ps1" @setParams

        if ($result) {
            Write-Host "  ✓ Account updated successfully!" -ForegroundColor Green
            $successCount++
            $results += [PSCustomObject]@{
                UserID = $account.UserID
                OldEmail = $account.Email
                NewEmail = $newEmail
                OldUserName = $account.UserName
                NewUserName = $newUserName
                Status = "Success"
                Error = $null
            }
        } else {
            throw "Update returned null result"
        }
    }
    catch {
        Write-Host "  ✗ Failed to update account: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
        $results += [PSCustomObject]@{
            UserID = $account.UserID
            OldEmail = $account.Email
            NewEmail = "N/A"
            OldUserName = $account.UserName
            NewUserName = "N/A"
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
}

# Summary
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Summary                                                     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Total accounts processed: $($accountsToFix.Count)" -ForegroundColor White
Write-Host "Successfully updated    : " -NoNewline
Write-Host $successCount -ForegroundColor Green
Write-Host "Failed                 : " -NoNewline
if ($failCount -gt 0) {
    Write-Host $failCount -ForegroundColor Red
} else {
    Write-Host $failCount -ForegroundColor Green
}

# Display results table
Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize UserID, OldEmail, NewEmail, Status -Wrap

if ($failCount -gt 0) {
    Write-Host "`nFailed accounts:" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq "Failed" } | ForEach-Object {
        Write-Host "  - $($_.OldEmail): $($_.Error)" -ForegroundColor Red
    }
}

Write-Host "`nDone!" -ForegroundColor Green

# Return results for pipeline usage
return $results
