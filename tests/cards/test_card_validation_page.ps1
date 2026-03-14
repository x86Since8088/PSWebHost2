#Requires -Version 7

<#
.SYNOPSIS
    Tests the card validation page by opening it as a card
.DESCRIPTION
    Opens the card validation page which auto-starts testing and submits results to server log
#>

$EnqueueScript = "..\..\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n=== Testing Card Validation Page ===" -ForegroundColor Cyan
Write-Host "Opening card validation test page..." -ForegroundColor Yellow

# Close all existing cards first
$closeResult = & $EnqueueScript `
    -Command 'closeAllCards' `
    -Type predefined `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($closeResult.Success) {
    $closeData = $closeResult.Result | ConvertFrom-Json
    Write-Host "Closed $($closeData.count) existing cards" -ForegroundColor Green
}

Start-Sleep -Seconds 2

# Open the card validation page (directly from public folder)
$openResult = & $EnqueueScript `
    -Command 'openCard' `
    -Type predefined `
    -Params @{
        url = '/public/card-validation-test.html'
        title = 'Card Validation Test'
    } `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 30

if ($openResult.Success) {
    $cardData = $openResult.Result | ConvertFrom-Json
    Write-Host "`n✓ Card opened successfully" -ForegroundColor Green
    Write-Host "  Card ID: $($cardData.cardId)" -ForegroundColor Gray
    Write-Host "  URL: $($cardData.url)" -ForegroundColor Gray

    Write-Host "`nThe validation page will auto-start testing and submit results to server log." -ForegroundColor Cyan
    Write-Host "Watch the card in your browser to see progress." -ForegroundColor Cyan
    Write-Host "`nResults will be logged to: /api/v1/debug/client-log" -ForegroundColor Yellow
    Write-Host "Category: CardValidation" -ForegroundColor Yellow
} else {
    Write-Host "`n✗ Failed to open card" -ForegroundColor Red
    $openResult | Format-List
}
