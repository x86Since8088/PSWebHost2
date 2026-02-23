#Requires -Version 7

<#
.SYNOPSIS
    Test all cards using file-based command queue
.DESCRIPTION
    Discovers cards from filesystem and tests them using the file-based queue system
#>

param(
    [string]$SessionID = "all",
    [int]$TimeoutSeconds = 15
)

$MyTag = '[Test-Cards-FileBased]'
$EnqueueScript = ".\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n$MyTag =====================================" -ForegroundColor Cyan
Write-Host "$MyTag Card Testing via File-Based Queue" -ForegroundColor Cyan
Write-Host "$MyTag =====================================" -ForegroundColor Cyan
Write-Host ""

# Discover all menu.yaml files
Write-Host "$MyTag Discovering cards from menu.yaml files..." -ForegroundColor Yellow

$menuFiles = Get-ChildItem -Path ".\apps" -Recurse -Filter "menu.yaml" -File -ErrorAction SilentlyContinue

Write-Host "$MyTag Found $($menuFiles.Count) menu.yaml files" -ForegroundColor Green

$allCards = @()

foreach ($menuFile in $menuFiles) {
    $appName = $menuFile.Directory.Parent.Name

    Write-Host "$MyTag Processing: $appName" -ForegroundColor Gray

    try {
        $menuContent = Get-Content $menuFile.FullName -Raw

        # Extract card URLs from menu items
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

                Write-Verbose "$MyTag   Found card: $name -> $url"
            }
        }
    } catch {
        Write-Warning "$MyTag Failed to parse $($menuFile.FullName): $_"
    }
}

Write-Host "$MyTag Total cards discovered: $($allCards.Count)" -ForegroundColor Green
Write-Host ""

if ($allCards.Count -eq 0) {
    Write-Warning "$MyTag No cards found to test"
    exit
}

# Test results
$testResults = @{
    Total = $allCards.Count
    Passed = 0
    Failed = 0
    Errors = @()
}

# Test each card
$cardNumber = 0
foreach ($card in $allCards) {
    $cardNumber++

    Write-Host "$MyTag [$cardNumber/$($allCards.Count)] Testing: $($card.Name)" -ForegroundColor Cyan
    Write-Host "$MyTag   URL: $($card.Url)" -ForegroundColor Gray

    try {
        # Build openCard command
        $params = @{
            url = $card.Url
            title = $card.Name
        }

        # Send openCard command
        Write-Verbose "$MyTag   Sending openCard command..."

        $result = & $EnqueueScript `
            -Command "openCard" `
            -Type predefined `
            -Params $params `
            -SessionID $SessionID `
            -Wait `
            -TimeoutSeconds $TimeoutSeconds

        if ($result.Success) {
            Write-Host "$MyTag   ✓ Card opened successfully" -ForegroundColor Green

            if ($result.Result) {
                Write-Host "$MyTag     Result: $($result.Result)" -ForegroundColor Gray
            }

            $testResults.Passed++

            # Small delay between cards
            Start-Sleep -Milliseconds 500

        } else {
            Write-Host "$MyTag   ✗ Failed: $($result.Error)" -ForegroundColor Red
            $testResults.Failed++
            $testResults.Errors += "$($card.Name): $($result.Error)"
        }

    } catch {
        Write-Host "$MyTag   ✗ Exception: $($_.Exception.Message)" -ForegroundColor Red
        $testResults.Failed++
        $testResults.Errors += "$($card.Name): $($_.Exception.Message)"
    }

    Write-Host ""
}

# Print summary
Write-Host "$MyTag =====================================" -ForegroundColor Cyan
Write-Host "$MyTag Test Summary" -ForegroundColor Cyan
Write-Host "$MyTag =====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "$MyTag Total Cards: $($testResults.Total)" -ForegroundColor White
Write-Host "$MyTag Passed:      $($testResults.Passed)" -ForegroundColor Green
Write-Host "$MyTag Failed:      $($testResults.Failed)" -ForegroundColor Red
Write-Host ""

if ($testResults.Failed -gt 0) {
    Write-Host "$MyTag Errors:" -ForegroundColor Red
    foreach ($error in $testResults.Errors) {
        Write-Host "$MyTag   - $error" -ForegroundColor Red
    }
    Write-Host ""
}

$passRate = if ($testResults.Total -gt 0) {
    [math]::Round(($testResults.Passed / $testResults.Total) * 100, 1)
} else { 0 }

Write-Host "$MyTag Pass Rate: $passRate%" -ForegroundColor $(
    if ($passRate -eq 100) { "Green" }
    elseif ($passRate -ge 75) { "Yellow" }
    else { "Red" }
)

Write-Host "$MyTag =====================================" -ForegroundColor Cyan
Write-Host ""
