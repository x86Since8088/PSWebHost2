# Account_Auth_BearerToken_RemoveTestingTokens.ps1
# Removes test bearer tokens (tokens with names starting with TA_Token_)

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Force,

    [switch]$SelectWithGridView,

    [switch]$RemoveUsers
)

$ErrorActionPreference = 'Stop'

# Get all test tokens
$getTokenScript = Join-Path $PSScriptRoot "Account_Auth_BearerToken_Get.ps1"
Write-Verbose "Retrieving test tokens..."
$testTokens = & $getTokenScript -TestTokensOnly

if (-not $testTokens) {
    Write-Host "No test tokens found" -ForegroundColor Yellow
    return
}

# Convert to array if single result
$testTokens = @($testTokens)

Write-Host "`nFound $($testTokens.Count) test token(s):" -ForegroundColor Cyan
$testTokens | Format-Table KeyID, Name, UserEmail, CreatedAt, LastUsed -AutoSize

# Determine which tokens to delete
$tokensToDelete = @()

if ($SelectWithGridView) {
    Write-Host "`nOpening GridView for selection..." -ForegroundColor Yellow
    $tokensToDelete = $testTokens | Out-GridView -Title "Select test tokens to delete" -OutputMode Multiple

    if (-not $tokensToDelete) {
        Write-Host "No tokens selected for deletion" -ForegroundColor Yellow
        return
    }
}
elseif ($Force) {
    # Delete all without confirmation
    $tokensToDelete = $testTokens
    Write-Host "`nDeleting all test tokens (Force mode)..." -ForegroundColor Yellow
}
else {
    # List only, no deletion
    Write-Host "`nTo delete these tokens, use one of the following:" -ForegroundColor Yellow
    Write-Host "  -Force                  : Delete all without confirmation" -ForegroundColor Gray
    Write-Host "  -SelectWithGridView     : Select tokens interactively" -ForegroundColor Gray
    Write-Host "  -RemoveUsers            : Also remove associated test users" -ForegroundColor Gray
    return
}

# Delete selected tokens
$removeTokenScript = Join-Path $PSScriptRoot "Account_Auth_BearerToken_Remove.ps1"
$deletedCount = 0
$failedCount = 0

foreach ($token in $tokensToDelete) {
    try {
        Write-Host "`nDeleting token: $($token.Name)..." -ForegroundColor Yellow

        $removeParams = @{
            KeyID = $token.KeyID
            Verbose = $VerbosePreference
        }

        if ($Force) {
            $removeParams['Force'] = $true
            $removeParams['Confirm'] = $false
        }

        if ($RemoveUsers) {
            $removeParams['RemoveUser'] = $true
        }

        & $removeTokenScript @removeParams

        $deletedCount++
    }
    catch {
        Write-Host "  Failed to delete $($token.Name): $($_.Exception.Message)" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Deletion Summary:" -ForegroundColor Cyan
Write-Host "  Deleted: $deletedCount" -ForegroundColor $(if ($deletedCount -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Failed:  $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "========================================`n" -ForegroundColor Cyan
