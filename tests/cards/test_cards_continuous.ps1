#Requires -Version 7

<#
.SYNOPSIS
    Continuously opens cards and monitors server logs for QA information
.DESCRIPTION
    Opens cards one by one, waits for DOM reports, logs all QA information to server
#>

param(
    [int]$DelayBetweenCards = 5,
    [int]$MaxCards = 0  # 0 = test all cards
)

$EnqueueScript = "..\..\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"
$MyTag = '[ContinuousTest]'

Write-Host "`n$MyTag ====================================" -ForegroundColor Cyan
Write-Host "$MyTag Continuous Card Testing with Logging" -ForegroundColor Cyan
Write-Host "$MyTag ====================================" -ForegroundColor Cyan
Write-Host ""

# Discover all cards from menu
Write-Host "$MyTag Discovering cards from menu..." -ForegroundColor Yellow

$menuFiles = Get-ChildItem -Path ".\apps" -Recurse -Filter "menu.yaml" -File -ErrorAction SilentlyContinue

$allCards = @()
foreach ($menuFile in $menuFiles) {
    $appName = $menuFile.Directory.Parent.Name

    try {
        $menuContent = Get-Content $menuFile.FullName -Raw
        $items = $menuContent -split '(?m)^- Name:'

        foreach ($item in $items) {
            if ([string]::IsNullOrWhiteSpace($item)) { continue }

            $name = if ($item -match '^\s*(.+?)[\r\n]') { $matches[1].Trim() } else { $null }
            $url = if ($item -match '(?m)^\s*url:\s*(.+?)[\r\n]') { $matches[1].Trim() } else { $null }

            if ($name -and $url) {
                $allCards += @{
                    Name = $name
                    Url = $url
                    AppName = $appName
                }
            }
        }
    } catch {
        Write-Warning "$MyTag Failed to parse $($menuFile.FullName): $_"
    }
}

Write-Host "$MyTag Found $($allCards.Count) cards" -ForegroundColor Green
Write-Host ""

# Limit cards if MaxCards specified
$cardsToTest = if ($MaxCards -gt 0) {
    $allCards | Select-Object -First $MaxCards
} else {
    $allCards
}

# Close all existing cards
Write-Host "$MyTag Closing all existing cards..." -ForegroundColor Yellow
$closeResult = & $EnqueueScript -Command 'closeAllCards' -Type predefined -SessionID all -Wait -TimeoutSeconds 15
if ($closeResult.Success) {
    $closeData = $closeResult.Result | ConvertFrom-Json
    Write-Host "$MyTag Closed $($closeData.count) cards" -ForegroundColor Green
}

Write-Host ""
Start-Sleep -Seconds 2

# Test each card
$cardNumber = 0
foreach ($card in $cardsToTest) {
    $cardNumber++

    Write-Host "$MyTag ─────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "$MyTag [$cardNumber/$($cardsToTest.Count)] $($card.Name)" -ForegroundColor Cyan
    Write-Host "$MyTag   URL: $($card.Url)" -ForegroundColor Gray
    Write-Host "$MyTag   App: $($card.AppName)" -ForegroundColor Gray

    try {
        # Open card
        Write-Host "$MyTag   → Opening..." -ForegroundColor Gray

        $openResult = & $EnqueueScript `
            -Command 'openCard' `
            -Type predefined `
            -Params @{url = $card.Url; title = $card.Name} `
            -SessionID all `
            -Wait `
            -TimeoutSeconds 30

        if ($openResult.Success) {
            $openData = $openResult.Result | ConvertFrom-Json
            $cardId = $openData.cardId
            Write-Host "$MyTag   ✓ Opened (ID: $cardId)" -ForegroundColor Green

            # Wait for card to fully load and report
            Write-Host "$MyTag   → Waiting for DOM to stabilize..." -ForegroundColor Gray
            Start-Sleep -Seconds $DelayBetweenCards

            # Validate card (will auto-log to server)
            Write-Host "$MyTag   → Validating..." -ForegroundColor Gray
            $validateResult = & $EnqueueScript `
                -Command 'validateCard' `
                -Type predefined `
                -Params @{cardId = $cardId} `
                -SessionID all `
                -Wait `
                -TimeoutSeconds 10

            if ($validateResult.Success) {
                $validation = $validateResult.Result | ConvertFrom-Json

                if ($validation.isValid) {
                    Write-Host "$MyTag   ✓ VALID - DOM detected, no errors" -ForegroundColor Green
                } elseif (-not $validation.hasDOM) {
                    Write-Host "$MyTag   ⚠ No DOM detected (may be iframe)" -ForegroundColor Yellow
                } elseif ($validation.hasError) {
                    Write-Host "$MyTag   ✗ Has $($validation.errorCount) error(s)" -ForegroundColor Red
                } else {
                    Write-Host "$MyTag   ⚠ Unknown validation state" -ForegroundColor Yellow
                }

                Write-Host "$MyTag   DOM nodes: $($validation.domNodeCount), Found by: $($validation.foundBy)" -ForegroundColor Gray
            } else {
                Write-Host "$MyTag   ⚠ Validation timeout" -ForegroundColor Yellow
            }

            # Close card
            Write-Host "$MyTag   → Closing..." -ForegroundColor Gray
            $closeResult = & $EnqueueScript `
                -Command 'closeCard' `
                -Type predefined `
                -Params @{cardId = $cardId} `
                -SessionID all `
                -Wait `
                -TimeoutSeconds 10

            if ($closeResult.Success) {
                Write-Host "$MyTag   ✓ Closed" -ForegroundColor Green
            } else {
                Write-Host "$MyTag   ⚠ Failed to close" -ForegroundColor Yellow
            }

        } else {
            Write-Host "$MyTag   ✗ Failed to open" -ForegroundColor Red
        }

    } catch {
        Write-Host "$MyTag   ✗ Exception: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""

    # Delay before next card
    if ($cardNumber -lt $cardsToTest.Count) {
        Start-Sleep -Seconds 2
    }
}

Write-Host "$MyTag ====================================" -ForegroundColor Cyan
Write-Host "$MyTag Testing Complete" -ForegroundColor Cyan
Write-Host "$MyTag ====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "$MyTag All validation results and DOM reports have been logged to server" -ForegroundColor Green
Write-Host ""
Write-Host "$MyTag To view results:" -ForegroundColor Yellow
Write-Host "$MyTag   1. Open System Log card" -ForegroundColor White
Write-Host "$MyTag   2. Filter by categories: CardValidation, IframeCardLoad" -ForegroundColor White
Write-Host "$MyTag   3. Review QA data and error reports" -ForegroundColor White
Write-Host ""
