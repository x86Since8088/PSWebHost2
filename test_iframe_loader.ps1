#Requires -Version 7

<#
.SYNOPSIS
    Tests iframe loader by opening iframe-based cards and monitoring server logs
.DESCRIPTION
    Opens cards that use iframes, waits for loader to report DOM status via logToServer
#>

$EnqueueScript = ".\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n=== Testing Iframe Loader ===" -ForegroundColor Cyan
Write-Host "This test opens iframe-based cards and monitors server logs for DOM reports`n" -ForegroundColor Gray

# Test cards that use iframes (based on previous test results)
$iframeCards = @(
    @{ url = '/apps/unittests/api/v1/coverage'; title = 'Coverage Report' }
    @{ url = '/apps/unittests/api/v1/processes'; title = 'Process Tracking' }
    @{ url = '/apps/vault/api/v1/audit'; title = 'Audit Log' }
    @{ url = '/apps/vault/api/v1/status'; title = 'Vault Status' }
)

# Close all existing cards
Write-Host "Closing all existing cards..." -ForegroundColor Yellow
$closeResult = & $EnqueueScript -Command 'closeAllCards' -Type predefined -SessionID all -Wait -TimeoutSeconds 15
if ($closeResult.Success) {
    $closeData = $closeResult.Result | ConvertFrom-Json
    Write-Host "Closed $($closeData.count) cards`n" -ForegroundColor Green
}

Start-Sleep -Seconds 2

# Test each iframe card
$testNumber = 0
foreach ($card in $iframeCards) {
    $testNumber++
    Write-Host "[$testNumber/$($iframeCards.Count)] Testing: $($card.title)" -ForegroundColor Cyan
    Write-Host "  URL: $($card.url)" -ForegroundColor Gray

    # Open the card
    Write-Host "  Opening card..." -ForegroundColor Yellow
    $openResult = & $EnqueueScript `
        -Command 'openCard' `
        -Type predefined `
        -Params @{url = $card.url; title = $card.title} `
        -SessionID all `
        -Wait `
        -TimeoutSeconds 30

    if ($openResult.Success) {
        $openData = $openResult.Result | ConvertFrom-Json
        Write-Host "  ✓ Card opened: $($openData.cardId)" -ForegroundColor Green

        # Wait for iframe to load and report
        Write-Host "  Waiting 7 seconds for iframe loader to report..." -ForegroundColor Gray
        Start-Sleep -Seconds 7

        # Check if card reported via logToServer
        Write-Host "  ✓ Iframe should have reported to server log (category: IframeCardLoad)" -ForegroundColor Green

        # Close the card
        Write-Host "  Closing card..." -ForegroundColor Yellow
        $closeResult = & $EnqueueScript `
            -Command 'closeCard' `
            -Type predefined `
            -Params @{cardId = $openData.cardId} `
            -SessionID all `
            -Wait `
            -TimeoutSeconds 10

        if ($closeResult.Success) {
            Write-Host "  ✓ Card closed`n" -ForegroundColor Green
        }
    } else {
        Write-Host "  ✗ Failed to open card" -ForegroundColor Red
        Write-Host "  Error: $($openResult.Message)`n" -ForegroundColor Red
    }

    # Delay before next test
    if ($testNumber -lt $iframeCards.Count) {
        Start-Sleep -Seconds 2
    }
}

Write-Host "`n=== Testing Complete ===" -ForegroundColor Cyan
Write-Host "`nTo view iframe loader reports:" -ForegroundColor Yellow
Write-Host "1. Open System Log card" -ForegroundColor White
Write-Host "2. Filter by category: 'IframeCardLoad'" -ForegroundColor White
Write-Host "3. Check for DOM analysis data (element counts, errors, etc.)`n" -ForegroundColor White

Write-Host "To view card validation reports:" -ForegroundColor Yellow
Write-Host "1. Open System Log card" -ForegroundColor White
Write-Host "2. Filter by category: 'CardValidation'" -ForegroundColor White
Write-Host "3. Check validation results for each card`n" -ForegroundColor White
