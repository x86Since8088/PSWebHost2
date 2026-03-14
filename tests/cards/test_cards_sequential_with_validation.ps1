#Requires -Version 7

<#
.SYNOPSIS
    Test cards sequentially with error detection
.DESCRIPTION
    Opens each card, checks for errors and "Failed to Load Component", then closes before next
#>

param(
    [string]$SessionID = "all",
    [int]$TimeoutSeconds = 30,
    [int]$DelayBetweenCards = 2
)

$MyTag = '[Card-Sequential-Validation]'
$EnqueueScript = "..\..\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n$MyTag =============================================" -ForegroundColor Cyan
Write-Host "$MyTag Sequential Card Validation with Error Detection" -ForegroundColor Cyan
Write-Host "$MyTag =============================================" -ForegroundColor Cyan
Write-Host ""

# Discover all cards
Write-Host "$MyTag Discovering cards..." -ForegroundColor Yellow

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

Write-Host "$MyTag Found $($allCards.Count) cards to test" -ForegroundColor Green
Write-Host ""

$results = @{
    Total = $allCards.Count
    Passed = 0
    Failed = 0
    Errors = @()
    FailedToLoad = @()
    Timeouts = @()
}

$cardNumber = 0

foreach ($card in $allCards) {
    $cardNumber++

    Write-Host "$MyTag =============================================" -ForegroundColor Cyan
    Write-Host "$MyTag [$cardNumber/$($allCards.Count)] Testing: $($card.Name)" -ForegroundColor Cyan
    Write-Host "$MyTag   App: $($card.AppName)" -ForegroundColor Gray
    Write-Host "$MyTag   URL: $($card.Url)" -ForegroundColor Gray
    Write-Host ""

    $cardId = $null
    $hasError = $false
    $hasFailedToLoad = $false
    $errorDetails = @()

    try {
        # Step 1: Open the card
        Write-Host "$MyTag   [1/4] Opening card..." -ForegroundColor Yellow

        $openResult = & $EnqueueScript `
            -Command "openCard" `
            -Type predefined `
            -Params @{ url = $card.Url; title = $card.Name } `
            -SessionID $SessionID `
            -Wait `
            -TimeoutSeconds $TimeoutSeconds

        if (-not $openResult.Success) {
            Write-Host "$MyTag   ✗ Failed to open: $($openResult.Error)" -ForegroundColor Red
            $results.Timeouts += "$($card.Name) ($($card.Url))"
            $results.Failed++
            continue
        }

        # Parse the result to get cardId
        try {
            $resultObj = $openResult.Result | ConvertFrom-Json
            $cardId = $resultObj.cardId
            Write-Host "$MyTag   ✓ Card opened: $cardId" -ForegroundColor Green
        } catch {
            Write-Host "$MyTag   ⚠ Card opened but couldn't parse cardId" -ForegroundColor Yellow
        }

        # Small delay for card to render
        Start-Sleep -Milliseconds 1000

        # Step 2: Check for "Failed to Load Component"
        Write-Host "$MyTag   [2/4] Checking for load failures..." -ForegroundColor Yellow

        if ($cardId) {
            $checkFailedLoad = & $EnqueueScript `
                -Command "document.getElementById('$cardId')?.textContent || ''" `
                -Type eval `
                -SessionID $SessionID `
                -Wait `
                -TimeoutSeconds 10

            if ($checkFailedLoad.Success -and $checkFailedLoad.Result) {
                if ($checkFailedLoad.Result -match "Failed to Load Component") {
                    $hasFailedToLoad = $true
                    Write-Host "$MyTag   ✗ FAILED TO LOAD COMPONENT DETECTED" -ForegroundColor Red
                    $errorDetails += "Failed to Load Component message found"
                } else {
                    Write-Host "$MyTag   ✓ No load failure detected" -ForegroundColor Green
                }
            }
        }

        # Step 3: Check for error elements
        Write-Host "$MyTag   [3/4] Checking for error elements..." -ForegroundColor Yellow

        if ($cardId) {
            $checkErrors = & $EnqueueScript `
                -Command "Array.from(document.getElementById('$cardId')?.querySelectorAll('.error, .error-message, [class*=\"error\"]') || []).map(e => e.textContent.substring(0, 100)).join(' | ')" `
                -Type eval `
                -SessionID $SessionID `
                -Wait `
                -TimeoutSeconds 10

            if ($checkErrors.Success -and $checkErrors.Result -and $checkErrors.Result.Trim() -ne "") {
                $hasError = $true
                Write-Host "$MyTag   ✗ ERROR ELEMENTS FOUND:" -ForegroundColor Red
                Write-Host "$MyTag     $($checkErrors.Result)" -ForegroundColor Red
                $errorDetails += "Error elements: $($checkErrors.Result)"
            } else {
                Write-Host "$MyTag   ✓ No error elements found" -ForegroundColor Green
            }
        }

        # Step 4: Close the card
        Write-Host "$MyTag   [4/4] Closing card..." -ForegroundColor Yellow

        if ($cardId) {
            $closeResult = & $EnqueueScript `
                -Command "closeCard" `
                -Type predefined `
                -Params @{ cardId = $cardId } `
                -SessionID $SessionID `
                -Wait `
                -TimeoutSeconds 10

            if ($closeResult.Success) {
                Write-Host "$MyTag   ✓ Card closed" -ForegroundColor Green
            } else {
                Write-Host "$MyTag   ⚠ Failed to close card" -ForegroundColor Yellow
            }
        } else {
            Write-Host "$MyTag   ⚠ No cardId, skipping close" -ForegroundColor Yellow
        }

        # Update results
        if ($hasError -or $hasFailedToLoad) {
            $results.Failed++

            $errorEntry = "$($card.Name) ($($card.Url))"
            if ($hasFailedToLoad) {
                $results.FailedToLoad += $errorEntry
            }
            if ($hasError) {
                $results.Errors += "$errorEntry - $($errorDetails -join '; ')"
            }

            Write-Host "$MyTag   ✗ VALIDATION FAILED" -ForegroundColor Red
        } else {
            $results.Passed++
            Write-Host "$MyTag   ✓ VALIDATION PASSED" -ForegroundColor Green
        }

    } catch {
        Write-Host "$MyTag   ✗ EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed++
        $results.Errors += "$($card.Name) ($($card.Url)) - Exception: $($_.Exception.Message)"
    }

    Write-Host ""

    # Delay between cards
    if ($cardNumber -lt $allCards.Count) {
        Write-Host "$MyTag   Waiting ${DelayBetweenCards}s before next card..." -ForegroundColor Gray
        Start-Sleep -Seconds $DelayBetweenCards
    }
}

# Print summary
Write-Host "$MyTag =============================================" -ForegroundColor Cyan
Write-Host "$MyTag VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "$MyTag =============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "$MyTag Total Cards Tested:  $($results.Total)" -ForegroundColor White
Write-Host "$MyTag Passed:              $($results.Passed)" -ForegroundColor Green
Write-Host "$MyTag Failed:              $($results.Failed)" -ForegroundColor Red
Write-Host ""

# Failed to Load Component
if ($results.FailedToLoad.Count -gt 0) {
    Write-Host "$MyTag CARDS WITH 'FAILED TO LOAD COMPONENT' ($($results.FailedToLoad.Count)):" -ForegroundColor Red
    foreach ($card in $results.FailedToLoad) {
        Write-Host "$MyTag   - $card" -ForegroundColor Red
    }
    Write-Host ""
}

# Errors
if ($results.Errors.Count -gt 0) {
    Write-Host "$MyTag CARDS WITH ERRORS ($($results.Errors.Count)):" -ForegroundColor Red
    foreach ($error in $results.Errors) {
        Write-Host "$MyTag   - $error" -ForegroundColor Red
    }
    Write-Host ""
}

# Timeouts
if ($results.Timeouts.Count -gt 0) {
    Write-Host "$MyTag CARDS THAT TIMED OUT ($($results.Timeouts.Count)):" -ForegroundColor Yellow
    foreach ($timeout in $results.Timeouts) {
        Write-Host "$MyTag   - $timeout" -ForegroundColor Yellow
    }
    Write-Host ""
}

$passRate = if ($results.Total -gt 0) {
    [math]::Round(($results.Passed / $results.Total) * 100, 1)
} else { 0 }

Write-Host "$MyTag Pass Rate: $passRate%" -ForegroundColor $(
    if ($passRate -eq 100) { "Green" }
    elseif ($passRate -ge 75) { "Yellow" }
    else { "Red" }
)

Write-Host "$MyTag =============================================" -ForegroundColor Cyan
Write-Host ""

# Save results to file
$reportPath = ".\CARD_VALIDATION_RESULTS_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').md"

$reportContent = @"
# Card Validation Results

**Date**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Total Cards**: $($results.Total)
**Passed**: $($results.Passed)
**Failed**: $($results.Failed)
**Pass Rate**: $passRate%

---

## Cards with "Failed to Load Component" ($($results.FailedToLoad.Count))

$( if ($results.FailedToLoad.Count -gt 0) {
    ($results.FailedToLoad | ForEach-Object { "- $_" }) -join "`n"
} else {
    "None"
})

---

## Cards with Errors ($($results.Errors.Count))

$( if ($results.Errors.Count -gt 0) {
    ($results.Errors | ForEach-Object { "- $_" }) -join "`n"
} else {
    "None"
})

---

## Cards that Timed Out ($($results.Timeouts.Count))

$( if ($results.Timeouts.Count -gt 0) {
    ($results.Timeouts | ForEach-Object { "- $_" }) -join "`n"
} else {
    "None"
})

---

**Report generated by**: test_cards_sequential_with_validation.ps1
"@

$reportContent | Out-File -FilePath $reportPath -Encoding UTF8 -Force

Write-Host "$MyTag Report saved to: $reportPath" -ForegroundColor Green
Write-Host ""

return $results
