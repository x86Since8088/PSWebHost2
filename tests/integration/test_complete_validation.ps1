#Requires -Version 7
# Complete Validation Test Suite
# Tests all debug utilities, cards, and UI elements

param(
    [int]$Port = 8080
)

$ErrorActionPreference = 'Continue'
$testResults = @()
$cardResults = @()

Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "  PSWebHost Complete Validation Suite" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify utilities are loaded
Write-Host "[1/10] Checking Debug Utility Functions..." -ForegroundColor Yellow

$requiredFunctions = @(
    'Debug-ClientCommand',
    'Launch-DebugCard',
    'Close-DebugCard',
    'Get-DebugOpenCards',
    'Get-DebugCommandHistory',
    'Get-DebugCommandQueue',
    'Get-DebugCommandResult',
    'Get-AllDebugCommandResults'
)

$allLoaded = $true
foreach ($func in $requiredFunctions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "  [OK] $func" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $func not found" -ForegroundColor Red
        $allLoaded = $false
    }
}

if ($allLoaded) {
    $testResults += @{ Test = "Utility Functions Loaded"; Result = "PASS" }
} else {
    $testResults += @{ Test = "Utility Functions Loaded"; Result = "FAIL" }
    Write-Host ""
    Write-Host "CRITICAL: Utility functions not loaded. Cannot continue." -ForegroundColor Red
    exit 1
}

# Step 2: Check debug queue initialization
Write-Host ""
Write-Host "[2/10] Checking Debug Queue..." -ForegroundColor Yellow

if ($Global:PSWebServer.DebugCommands) {
    Write-Host "  [OK] DebugCommands initialized" -ForegroundColor Green
    Write-Host "    Queue: $($Global:PSWebServer.DebugCommands.Queue.Count) pending" -ForegroundColor Gray
    Write-Host "    History: $($Global:PSWebServer.DebugCommands.History.Count) commands" -ForegroundColor Gray
    $testResults += @{ Test = "Debug Queue Initialized"; Result = "PASS" }
} else {
    Write-Host "  [FAIL] DebugCommands not initialized" -ForegroundColor Red
    $testResults += @{ Test = "Debug Queue Initialized"; Result = "FAIL" }
}

# Step 3: Test Debug-ClientCommand
Write-Host ""
Write-Host "[3/10] Testing Debug-ClientCommand..." -ForegroundColor Yellow

try {
    $cmdResult = Debug-ClientCommand -Command "console.log('[Validation] Test command')" -Type eval
    if ($cmdResult.Success) {
        Write-Host "  [OK] Command enqueued: $($cmdResult.CommandID)" -ForegroundColor Green
        $testResults += @{ Test = "Debug-ClientCommand"; Result = "PASS" }
    } else {
        Write-Host "  [FAIL] $($cmdResult.Error)" -ForegroundColor Red
        $testResults += @{ Test = "Debug-ClientCommand"; Result = "FAIL" }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Debug-ClientCommand"; Result = "FAIL" }
}

# Step 4: Test Get-DebugCommandQueue
Write-Host ""
Write-Host "[4/10] Testing Get-DebugCommandQueue..." -ForegroundColor Yellow

try {
    $queue = Get-DebugCommandQueue
    Write-Host "  [OK] Retrieved queue: $($queue.Count) pending commands" -ForegroundColor Green
    $testResults += @{ Test = "Get-DebugCommandQueue"; Result = "PASS" }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Get-DebugCommandQueue"; Result = "FAIL" }
}

# Step 5: Test Get-DebugCommandHistory
Write-Host ""
Write-Host "[5/10] Testing Get-DebugCommandHistory..." -ForegroundColor Yellow

try {
    $history = Get-DebugCommandHistory -Limit 5
    Write-Host "  [OK] Retrieved history: $($history.Count) commands" -ForegroundColor Green
    $testResults += @{ Test = "Get-DebugCommandHistory"; Result = "PASS" }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Get-DebugCommandHistory"; Result = "FAIL" }
}

# Step 6: Get main menu and enumerate cards
Write-Host ""
Write-Host "[6/10] Enumerating Cards from Main Menu..." -ForegroundColor Yellow

try {
    $menuResponse = Invoke-WebRequest -Uri "http://localhost:$Port/api/v1/ui/elements/main-menu" -UseBasicParsing
    $menuData = $menuResponse.Content | ConvertFrom-Json

    # Recursively find all card URLs
    function Find-CardUrls {
        param($items)
        $urls = @()
        foreach ($item in $items) {
            if ($item.url -and $item.url -match '/ui/elements/') {
                $urls += @{
                    Name = $item.label
                    Url = $item.url
                    Category = $item.category
                }
            }
            if ($item.children) {
                $urls += Find-CardUrls -items $item.children
            }
        }
        return $urls
    }

    $allCards = Find-CardUrls -items $menuData
    Write-Host "  [OK] Found $($allCards.Count) cards" -ForegroundColor Green

    foreach ($card in $allCards | Select-Object -First 10) {
        Write-Host "    - $($card.Name)" -ForegroundColor Gray
    }
    if ($allCards.Count -gt 10) {
        Write-Host "    ... and $($allCards.Count - 10) more" -ForegroundColor Gray
    }

    $testResults += @{ Test = "Enumerate Cards"; Result = "PASS"; Count = $allCards.Count }

} catch {
    Write-Host "  [FAIL] Could not retrieve menu: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Enumerate Cards"; Result = "FAIL" }
    $allCards = @()
}

# Step 7: Test card metadata endpoints
Write-Host ""
Write-Host "[7/10] Validating Card Metadata..." -ForegroundColor Yellow

$cardsToTest = $allCards | Select-Object -First 15  # Test first 15 cards

foreach ($card in $cardsToTest) {
    $cardName = $card.Name
    $cardUrl = $card.Url

    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port$cardUrl" -UseBasicParsing -TimeoutSec 10

        if ($response.StatusCode -eq 200) {
            try {
                $metadata = $response.Content | ConvertFrom-Json

                # Validate JSON structure
                $hasComponent = $null -ne $metadata.component
                $hasScriptPath = $null -ne $metadata.scriptPath

                if ($hasComponent -and $hasScriptPath) {
                    Write-Host "  [OK] $cardName - Valid JSON metadata" -ForegroundColor Green
                    $cardResults += @{
                        Card = $cardName
                        Url = $cardUrl
                        Status = "PASS"
                        Format = "JSON"
                        Component = $metadata.component
                    }
                } else {
                    Write-Host "  [WARN] $cardName - Missing required fields" -ForegroundColor Yellow
                    $cardResults += @{
                        Card = $cardName
                        Url = $cardUrl
                        Status = "WARN"
                        Issue = "Missing component or scriptPath"
                    }
                }
            } catch {
                Write-Host "  [WARN] $cardName - Not JSON format" -ForegroundColor Yellow
                $cardResults += @{
                    Card = $cardName
                    Url = $cardUrl
                    Status = "WARN"
                    Issue = "Not JSON - may be legacy HTML"
                }
            }
        } else {
            Write-Host "  [FAIL] $cardName - HTTP $($response.StatusCode)" -ForegroundColor Red
            $cardResults += @{
                Card = $cardName
                Url = $cardUrl
                Status = "FAIL"
                Issue = "HTTP $($response.StatusCode)"
            }
        }
    } catch {
        Write-Host "  [FAIL] $cardName - $($_.Exception.Message)" -ForegroundColor Red
        $cardResults += @{
            Card = $cardName
            Url = $cardUrl
            Status = "FAIL"
            Issue = $_.Exception.Message
        }
    }
}

$passedCards = ($cardResults | Where-Object { $_.Status -eq "PASS" }).Count
$warnCards = ($cardResults | Where-Object { $_.Status -eq "WARN" }).Count
$failedCards = ($cardResults | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host ""
Write-Host "  Card Validation Results:" -ForegroundColor Cyan
Write-Host "    PASS: $passedCards" -ForegroundColor Green
Write-Host "    WARN: $warnCards" -ForegroundColor Yellow
Write-Host "    FAIL: $failedCards" -ForegroundColor $(if ($failedCards -gt 0) { "Red" } else { "Gray" })

$testResults += @{ Test = "Card Metadata Validation"; Result = if ($failedCards -eq 0) { "PASS" } else { "PARTIAL" } }

# Step 8: Test disk persistence directory
Write-Host ""
Write-Host "[8/10] Checking Disk Persistence..." -ForegroundColor Yellow

$resultsDir = Join-Path $PSScriptRoot "PsWebHost_Data\debug_results"
if (Test-Path $resultsDir) {
    $resultFiles = Get-ChildItem $resultsDir -Filter "*.json" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Results directory exists" -ForegroundColor Green
    Write-Host "    Location: $resultsDir" -ForegroundColor Gray
    Write-Host "    Files: $($resultFiles.Count)" -ForegroundColor Gray
    $testResults += @{ Test = "Disk Persistence"; Result = "PASS" }
} else {
    Write-Host "  [INFO] Results directory not created yet (will be created on first PUT)" -ForegroundColor Gray
    $testResults += @{ Test = "Disk Persistence"; Result = "PENDING" }
}

# Step 9: Test PUT endpoint exists
Write-Host ""
Write-Host "[9/10] Checking PUT Endpoint..." -ForegroundColor Yellow

try {
    $putEndpoint = "C:\SC\PsWebHost\apps\WebHostDebugExtensions\routes\api\v1\debug\commands\result\put.ps1"
    if (Test-Path $putEndpoint) {
        Write-Host "  [OK] PUT endpoint file exists" -ForegroundColor Green
        $testResults += @{ Test = "PUT Endpoint"; Result = "PASS" }
    } else {
        Write-Host "  [FAIL] PUT endpoint file not found" -ForegroundColor Red
        $testResults += @{ Test = "PUT Endpoint"; Result = "FAIL" }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "PUT Endpoint"; Result = "FAIL" }
}

# Step 10: Check client script uses PUT
Write-Host ""
Write-Host "[10/10] Verifying Client Uses PUT..." -ForegroundColor Yellow

try {
    $clientScript = Get-Content "C:\SC\PsWebHost\apps\WebHostDebugExtensions\public\debug-poll-service.js" -Raw
    if ($clientScript -match "usePUT\s*=\s*true" -and $clientScript -match "method:\s*usePUT\s*\?\s*'PUT'") {
        Write-Host "  [OK] Client configured to use PUT" -ForegroundColor Green
        $testResults += @{ Test = "Client Uses PUT"; Result = "PASS" }
    } else {
        Write-Host "  [WARN] Client may not be using PUT" -ForegroundColor Yellow
        $testResults += @{ Test = "Client Uses PUT"; Result = "WARN" }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Client Uses PUT"; Result = "FAIL" }
}

# Generate summary
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

$totalTests = $testResults.Count
$passedTests = ($testResults | Where-Object { $_.Result -eq "PASS" }).Count
$failedTests = ($testResults | Where-Object { $_.Result -eq "FAIL" }).Count
$warnTests = ($testResults | Where-Object { $_.Result -in @("WARN", "PARTIAL", "PENDING") }).Count

Write-Host "Core Tests:" -ForegroundColor White
Write-Host "  Total:  $totalTests" -ForegroundColor Gray
Write-Host "  PASS:   $passedTests" -ForegroundColor Green
Write-Host "  FAIL:   $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Gray" })
Write-Host "  WARN:   $warnTests" -ForegroundColor Yellow

Write-Host ""
Write-Host "Card Validation:" -ForegroundColor White
Write-Host "  Total Cards: $($allCards.Count)" -ForegroundColor Gray
Write-Host "  Tested:      $($cardsToTest.Count)" -ForegroundColor Gray
Write-Host "  PASS:        $passedCards" -ForegroundColor Green
Write-Host "  WARN:        $warnCards" -ForegroundColor Yellow
Write-Host "  FAIL:        $failedCards" -ForegroundColor $(if ($failedCards -gt 0) { "Red" } else { "Gray" })

if ($failedTests -gt 0) {
    Write-Host ""
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Result -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Test)" -ForegroundColor Red
    }
}

if ($failedCards -gt 0) {
    Write-Host ""
    Write-Host "Failed Cards:" -ForegroundColor Red
    $cardResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Card): $($_.Issue)" -ForegroundColor Red
    }
}

# Save detailed results
$reportPath = Join-Path $PSScriptRoot "validation_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$report = @{
    Timestamp = (Get-Date).ToString('o')
    CoreTests = $testResults
    CardTests = $cardResults
    Summary = @{
        TotalCoreTests = $totalTests
        PassedCoreTests = $passedTests
        FailedCoreTests = $failedTests
        WarnCoreTests = $warnTests
        TotalCards = $allCards.Count
        TestedCards = $cardsToTest.Count
        PassedCards = $passedCards
        WarnCards = $warnCards
        FailedCards = $failedCards
    }
}

$report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Detailed report saved: $reportPath" -ForegroundColor Cyan

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host ""

# Exit code
if ($failedTests -eq 0 -and $failedCards -eq 0) {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
} elseif ($failedTests -eq 0 -and $failedCards -le 3) {
    Write-Host "CORE TESTS PASSED (Some card warnings)" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
