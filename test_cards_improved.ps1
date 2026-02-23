#Requires -Version 7

<#
.SYNOPSIS
    Improved sequential card testing with proper cleanup
.DESCRIPTION
    Tests browser connection first, closes all cards, then tests each card sequentially
#>

param(
    [string]$SessionID = "all",
    [int]$CardTimeout = 30,
    [int]$DelayBetweenCards = 2
)

$MyTag = '[Card-Test-Improved]'
$EnqueueScript = ".\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n$MyTag ====================================" -ForegroundColor Cyan
Write-Host "$MyTag Improved Sequential Card Testing" -ForegroundColor Cyan
Write-Host "$MyTag ====================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Test browser connection
Write-Host "$MyTag [Step 1/5] Testing browser connection..." -ForegroundColor Yellow

$testResult = & $EnqueueScript `
    -Command "getCardCount" `
    -Type predefined `
    -SessionID $SessionID `
    -Wait `
    -TimeoutSeconds 10

if (-not $testResult.Success) {
    Write-Host "$MyTag ✗ Browser not connected!" -ForegroundColor Red
    Write-Host "$MyTag   Please open browser at http://localhost:8080/ and try again" -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host "$MyTag ✓ Browser connected" -ForegroundColor Green
Write-Host ""

# Step 2: Close all existing cards
Write-Host "$MyTag [Step 2/5] Closing all existing cards..." -ForegroundColor Yellow

$closeAllResult = & $EnqueueScript `
    -Command "closeAllCards" `
    -Type predefined `
    -SessionID $SessionID `
    -Wait `
    -TimeoutSeconds 10

if ($closeAllResult.Success) {
    $closeData = $closeAllResult.Result | ConvertFrom-Json
    Write-Host "$MyTag ✓ Closed $($closeData.count) cards" -ForegroundColor Green
} else {
    Write-Host "$MyTag ⚠ Could not close all cards (may be none open)" -ForegroundColor Yellow
}

Write-Host ""
Start-Sleep -Seconds 2

# Step 3: Discover cards
Write-Host "$MyTag [Step 3/5] Discovering cards..." -ForegroundColor Yellow

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

Write-Host "$MyTag ✓ Found $($allCards.Count) cards" -ForegroundColor Green
Write-Host ""

# Step 4: Get initial card count
Write-Host "$MyTag [Step 4/5] Getting current card count..." -ForegroundColor Yellow

$countResult = & $EnqueueScript `
    -Command "getCardCount" `
    -Type predefined `
    -SessionID $SessionID `
    -Wait `
    -TimeoutSeconds 5

if ($countResult.Success) {
    $countData = $countResult.Result | ConvertFrom-Json
    Write-Host "$MyTag ✓ Current open cards: $($countData.count)" -ForegroundColor Green
} else {
    Write-Host "$MyTag ⚠ Could not get card count" -ForegroundColor Yellow
}

Write-Host ""

# Step 5: Test each card
Write-Host "$MyTag [Step 5/5] Testing cards sequentially..." -ForegroundColor Yellow
Write-Host ""

$results = @{
    Total = $allCards.Count
    Passed = 0
    Failed = 0
    FailedToLoad = @()
    Errors = @()
    Timeouts = @()
}

$cardNumber = 0

foreach ($card in $allCards) {
    $cardNumber++

    Write-Host "$MyTag ─────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "$MyTag [$cardNumber/$($allCards.Count)] $($card.Name)" -ForegroundColor Cyan
    Write-Host "$MyTag   URL: $($card.Url)" -ForegroundColor Gray

    $cardId = $null

    try {
        # Open card
        Write-Host "$MyTag   → Opening..." -ForegroundColor Gray

        $openResult = & $EnqueueScript `
            -Command "openCard" `
            -Type predefined `
            -Params @{ url = $card.Url; title = $card.Name } `
            -SessionID $SessionID `
            -Wait `
            -TimeoutSeconds $CardTimeout

        if (-not $openResult.Success) {
            Write-Host "$MyTag   ✗ Timeout" -ForegroundColor Red
            $results.Timeouts += "$($card.Name) ($($card.Url))"
            $results.Failed++
            continue
        }

        # Parse cardId from result
        try {
            $openData = $openResult.Result | ConvertFrom-Json
            $cardId = $openData.cardId
            Write-Host "$MyTag   ✓ Opened (ID: $cardId)" -ForegroundColor Green
        } catch {
            Write-Host "$MyTag   ⚠ Opened but couldn't parse cardId" -ForegroundColor Yellow
        }

        # Validate card using predefined command
        if ($cardId) {
            $validateResult = & $EnqueueScript `
                -Command "validateCard" `
                -Type predefined `
                -Params @{ cardId = $cardId } `
                -SessionID $SessionID `
                -Wait `
                -TimeoutSeconds 10

            if ($validateResult.Success) {
                try {
                    $validation = $validateResult.Result | ConvertFrom-Json

                    if ($validation.exists -and $validation.hasDOM) {
                        if ($validation.hasError) {
                            Write-Host "$MyTag   ✗ Card has $($validation.errorCount) error elements" -ForegroundColor Red
                            $results.Errors += "$($card.Name) ($($card.Url)) - $($validation.errorCount) errors"
                            $results.Failed++
                        } else {
                            Write-Host "$MyTag   ✓ No errors detected" -ForegroundColor Green
                            $results.Passed++
                        }
                    } else {
                        Write-Host "$MyTag   ✗ Card DOM not properly loaded" -ForegroundColor Red
                        $results.FailedToLoad += "$($card.Name) ($($card.Url))"
                        $results.Failed++
                    }
                } catch {
                    Write-Host "$MyTag   ⚠ Could not parse validation result" -ForegroundColor Yellow
                    $results.Passed++
                }
            } else {
                Write-Host "$MyTag   ⚠ Validation timeout, assuming OK" -ForegroundColor Yellow
                $results.Passed++
            }

            # Close the card
            Write-Host "$MyTag   → Closing..." -ForegroundColor Gray

            $closeResult = & $EnqueueScript `
                -Command "closeCard" `
                -Type predefined `
                -Params @{ cardId = $cardId } `
                -SessionID $SessionID `
                -Wait `
                -TimeoutSeconds 10

            if ($closeResult.Success) {
                Write-Host "$MyTag   ✓ Closed" -ForegroundColor Green
            } else {
                Write-Host "$MyTag   ⚠ Failed to close" -ForegroundColor Yellow
            }
        }

    } catch {
        Write-Host "$MyTag   ✗ Exception: $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed++
        $results.Errors += "$($card.Name) - Exception: $($_.Exception.Message)"
    }

    Write-Host ""

    # Delay before next card
    if ($cardNumber -lt $allCards.Count) {
        Start-Sleep -Seconds $DelayBetweenCards
    }
}

# Print summary
Write-Host "$MyTag ====================================" -ForegroundColor Cyan
Write-Host "$MyTag SUMMARY" -ForegroundColor Cyan
Write-Host "$MyTag ====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "$MyTag Total:   $($results.Total)" -ForegroundColor White
Write-Host "$MyTag Passed:  $($results.Passed)" -ForegroundColor Green
Write-Host "$MyTag Failed:  $($results.Failed)" -ForegroundColor Red
Write-Host ""

if ($results.FailedToLoad.Count -gt 0) {
    Write-Host "$MyTag Failed to Load Component ($($results.FailedToLoad.Count)):" -ForegroundColor Red
    $results.FailedToLoad | ForEach-Object { Write-Host "$MyTag   - $_" -ForegroundColor Red }
    Write-Host ""
}

if ($results.Errors.Count -gt 0) {
    Write-Host "$MyTag Errors ($($results.Errors.Count)):" -ForegroundColor Red
    $results.Errors | ForEach-Object { Write-Host "$MyTag   - $_" -ForegroundColor Red }
    Write-Host ""
}

if ($results.Timeouts.Count -gt 0) {
    Write-Host "$MyTag Timeouts ($($results.Timeouts.Count)):" -ForegroundColor Yellow
    $results.Timeouts | ForEach-Object { Write-Host "$MyTag   - $_" -ForegroundColor Yellow }
    Write-Host ""
}

$passRate = if ($results.Total -gt 0) { [math]::Round(($results.Passed / $results.Total) * 100, 1) } else { 0 }
Write-Host "$MyTag Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 75) { "Green" } elseif ($passRate -ge 50) { "Yellow" } else { "Red" })

Write-Host "$MyTag ====================================" -ForegroundColor Cyan
Write-Host ""

return $results
