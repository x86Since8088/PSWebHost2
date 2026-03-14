#Requires -Version 7

<#
.SYNOPSIS
    Investigate card timeout issues
.DESCRIPTION
    Test a few cards with extended timeout and detailed logging
#>

param(
    [string]$SessionID = "all",
    [int]$TimeoutSeconds = 45
)

$MyTag = '[Card-Timeout-Investigation]'
$EnqueueScript = "..\..\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n$MyTag ========================================" -ForegroundColor Cyan
Write-Host "$MyTag Card Timeout Investigation" -ForegroundColor Cyan
Write-Host "$MyTag ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "$MyTag Timeout: ${TimeoutSeconds}s" -ForegroundColor Gray
Write-Host "$MyTag SessionID: $SessionID" -ForegroundColor Gray
Write-Host ""

# Test cards that passed before
$testCards = @(
    @{ Name = "Linux Services"; Url = "/apps/linuxadmin/cards/linux-services" }
    @{ Name = "Server Metrics"; Url = "/apps/WebHostMetrics/cards/server-heatmap" }
    @{ Name = "Chart Builder"; Url = "/apps/uplot/api/v1/ui/elements/uplot-home" }
)

# Also test a card that timed out before
$testCards += @{ Name = "Debug Console"; Url = "/apps/WebHostDebugExtensions/cards/debug-console" }
$testCards += @{ Name = "File Explorer"; Url = "/apps/WebhostFileExplorer/cards/file-explorer" }

Write-Host "$MyTag Testing $($testCards.Count) cards..." -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($card in $testCards) {
    Write-Host "$MyTag ==========================================" -ForegroundColor Cyan
    Write-Host "$MyTag Testing: $($card.Name)" -ForegroundColor Cyan
    Write-Host "$MyTag   URL: $($card.Url)" -ForegroundColor Gray
    Write-Host ""

    $startTime = Get-Date

    try {
        Write-Host "$MyTag   [Step 1] Enqueueing openCard command..." -ForegroundColor Yellow

        $params = @{
            url = $card.Url
            title = $card.Name
        }

        $result = & $EnqueueScript `
            -Command "openCard" `
            -Type predefined `
            -Params $params `
            -SessionID $SessionID `
            -Wait `
            -TimeoutSeconds $TimeoutSeconds `
            -Verbose

        $duration = ((Get-Date) - $startTime).TotalSeconds

        Write-Host ""
        Write-Host "$MyTag   [Result] Duration: $([math]::Round($duration, 2))s" -ForegroundColor Gray

        if ($result.Success) {
            Write-Host "$MyTag   ✓ SUCCESS" -ForegroundColor Green
            Write-Host "$MyTag     Status: $($result.Status)" -ForegroundColor Green
            Write-Host "$MyTag     ExecutionTime: $($result.ExecutionTimeMs)ms" -ForegroundColor Gray

            if ($result.Result) {
                Write-Host "$MyTag     Result:" -ForegroundColor Gray
                $result.Result | ConvertTo-Json -Depth 3 | ForEach-Object {
                    Write-Host "$MyTag       $_" -ForegroundColor Gray
                }
            }

            $results += @{
                Card = $card.Name
                Status = "Success"
                Duration = $duration
                ExecutionTimeMs = $result.ExecutionTimeMs
                Result = $result.Result
            }

        } else {
            Write-Host "$MyTag   ✗ FAILED" -ForegroundColor Red
            Write-Host "$MyTag     Error: $($result.Error)" -ForegroundColor Red
            Write-Host "$MyTag     Message: $($result.Message)" -ForegroundColor Red

            $results += @{
                Card = $card.Name
                Status = "Failed"
                Duration = $duration
                Error = $result.Error
                Message = $result.Message
            }
        }

    } catch {
        $duration = ((Get-Date) - $startTime).TotalSeconds

        Write-Host ""
        Write-Host "$MyTag   ✗ EXCEPTION" -ForegroundColor Red
        Write-Host "$MyTag     $($_.Exception.Message)" -ForegroundColor Red

        $results += @{
            Card = $card.Name
            Status = "Exception"
            Duration = $duration
            Error = $_.Exception.Message
        }
    }

    Write-Host ""

    # Small delay between cards
    Start-Sleep -Milliseconds 1000
}

# Print summary
Write-Host "$MyTag ==========================================" -ForegroundColor Cyan
Write-Host "$MyTag Summary" -ForegroundColor Cyan
Write-Host "$MyTag ==========================================" -ForegroundColor Cyan
Write-Host ""

$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
$failedCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count
$exceptionCount = ($results | Where-Object { $_.Status -eq "Exception" }).Count

Write-Host "$MyTag Total Tested: $($results.Count)" -ForegroundColor White
Write-Host "$MyTag Success:      $successCount" -ForegroundColor Green
Write-Host "$MyTag Failed:       $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Gray" })
Write-Host "$MyTag Exceptions:   $exceptionCount" -ForegroundColor $(if ($exceptionCount -gt 0) { "Red" } else { "Gray" })
Write-Host ""

Write-Host "$MyTag Results:" -ForegroundColor Cyan
foreach ($result in $results) {
    $statusColor = switch ($result.Status) {
        "Success" { "Green" }
        "Failed" { "Red" }
        "Exception" { "Red" }
        default { "Yellow" }
    }

    $statusSymbol = switch ($result.Status) {
        "Success" { "✓" }
        "Failed" { "✗" }
        "Exception" { "⚠" }
        default { "?" }
    }

    Write-Host "$MyTag   $statusSymbol $($result.Card) - $($result.Status) ($([math]::Round($result.Duration, 2))s)" -ForegroundColor $statusColor

    if ($result.Error) {
        Write-Host "$MyTag     Error: $($result.Error)" -ForegroundColor Red
    }
    if ($result.Message) {
        Write-Host "$MyTag     Message: $($result.Message)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "$MyTag ==========================================" -ForegroundColor Cyan
Write-Host ""

# Output results for further analysis
return $results
