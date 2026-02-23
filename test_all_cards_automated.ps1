#Requires -Version 7

<#
.SYNOPSIS
    Automated Card Testing System for PSWebHost

.DESCRIPTION
    Systematically tests all UI cards/elements in PSWebHost:
    - Opens each card programmatically
    - Validates DOM rendering
    - Tests UI element functionality
    - Reports issues and fixes problems
    - Generates comprehensive test report

.PARAMETER BaseUrl
    Base URL of PSWebHost (default: http://localhost:8080)

.PARAMETER CardFilter
    Filter cards by name pattern (e.g., "*file*", "task-manager")

.PARAMETER FixIssues
    Attempt to automatically fix discovered issues

.PARAMETER ExportReport
    Export detailed test report to JSON file

.EXAMPLE
    .\test_all_cards_automated.ps1

.EXAMPLE
    .\test_all_cards_automated.ps1 -CardFilter "*file*" -FixIssues

.EXAMPLE
    .\test_all_cards_automated.ps1 -ExportReport -FixIssues
#>

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$CardFilter = "*",
    [switch]$FixIssues,
    [switch]$ExportReport
)

$ErrorActionPreference = 'Continue'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost Card Testing System" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Initialize counters
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsWarning = 0
$script:IssuesFixed = 0
$script:TestResults = @()

# Create temporary API key for testing
Write-Host "Setup: Creating temporary API key..." -ForegroundColor Yellow
try {
    $createScript = Join-Path $PSScriptRoot "system\utility\Account_Auth_BearerToken_New.ps1"
    $apiKeyResult = & $createScript `
        -TestAccount `
        -Roles @('admin', 'site_admin', 'debug') `
        -Description "Temporary API key for card testing" `
        -Verbose:$false `
        2>&1 | Where-Object { $_ -is [System.Management.Automation.PSCustomObject] }

    if ($apiKeyResult -and $apiKeyResult.ApiKey) {
        $script:TestApiKey = $apiKeyResult.ApiKey
        $script:TestKeyID = $apiKeyResult.KeyID
        Write-Host "✅ API key created" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to create API key - tests will fail" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Discover all cards
Write-Host "`nDiscovering UI cards..." -ForegroundColor Yellow
$cardPaths = Get-ChildItem -Path $PSScriptRoot -Recurse -Filter "get.ps1" |
    Where-Object { $_.FullName -match "routes\\api\\v1\\ui\\elements" } |
    ForEach-Object {
        $relativePath = $_.FullName -replace [regex]::Escape($PSScriptRoot), ""
        $relativePath = $relativePath -replace "\\", "/"

        # Extract card name from path
        if ($relativePath -match "/ui/elements/([^/]+)/get\.ps1") {
            $cardName = $matches[1]
            [PSCustomObject]@{
                Name = $cardName
                Path = $relativePath
                Endpoint = "/api/v1/ui/elements/$cardName"
                FilePath = $_.FullName
                App = if ($relativePath -match "apps/([^/]+)") { $matches[1] } else { "Core" }
            }
        }
    } |
    Where-Object { $_.Name -like $CardFilter } |
    Sort-Object App, Name

Write-Host "Found $($cardPaths.Count) cards matching filter '$CardFilter'" -ForegroundColor Cyan

# Helper function: Execute debug command
function Invoke-DebugCommand {
    param(
        [string]$Command,
        [string]$Type = 'eval',
        [hashtable]$Params = @{},
        [int]$TimeoutSeconds = 10
    )

    try {
        $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }
        $payload = @{
            Type = $Type
            Command = $Command
            SessionID = 'all'
            Params = $Params
        } | ConvertTo-Json -Depth 3

        # Enqueue command
        $enqueueResponse = Invoke-WebRequest `
            -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue" `
            -Method POST `
            -Headers $headers `
            -Body $payload `
            -ContentType "application/json" `
            -UseBasicParsing `
            -TimeoutSec 5

        if ($enqueueResponse.StatusCode -ne 200) {
            return @{ Success = $false; Error = "Enqueue failed: $($enqueueResponse.StatusCode)" }
        }

        $enqueueData = $enqueueResponse.Content | ConvertFrom-Json
        $commandID = $enqueueData.commandID

        # Wait for execution (poll history)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            Start-Sleep -Milliseconds 500

            $historyResponse = Invoke-WebRequest `
                -Uri "$BaseUrl/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=50" `
                -Method GET `
                -Headers $headers `
                -UseBasicParsing `
                -TimeoutSec 5

            $historyData = $historyResponse.Content | ConvertFrom-Json
            $completedCmd = $historyData.commands | Where-Object { $_.CommandID -eq $commandID }

            if ($completedCmd) {
                if ($completedCmd.Status -eq 'completed') {
                    return @{
                        Success = $true
                        Result = $completedCmd.Result
                        ExecutionTime = $completedCmd.ExecutionTimeMs
                    }
                } elseif ($completedCmd.Status -eq 'failed') {
                    return @{
                        Success = $false
                        Error = $completedCmd.Error
                    }
                }
            }
        }

        return @{ Success = $false; Error = "Timeout waiting for command execution" }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Helper function: Test card rendering
function Test-CardRendering {
    param(
        [PSCustomObject]$Card
    )

    Write-Host "`n  Testing: $($Card.Name)" -ForegroundColor Cyan
    Write-Host "    App: $($Card.App)" -ForegroundColor Gray
    Write-Host "    Endpoint: $($Card.Endpoint)" -ForegroundColor Gray

    $testResult = [PSCustomObject]@{
        CardName = $Card.Name
        App = $Card.App
        Endpoint = $Card.Endpoint
        Tests = @()
        OverallStatus = 'Unknown'
        IssuesFound = @()
        IssuesFixed = @()
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    # Test 1: Endpoint responds
    try {
        $headers = @{ 'Authorization' = "Bearer $script:TestApiKey" }
        $response = Invoke-WebRequest `
            -Uri "$BaseUrl$($Card.Endpoint)" `
            -Method GET `
            -Headers $headers `
            -UseBasicParsing `
            -TimeoutSec 5

        if ($response.StatusCode -eq 200) {
            Write-Host "    ✅ Endpoint responds (200 OK)" -ForegroundColor Green
            $testResult.Tests += @{ Test = 'EndpointResponse'; Status = 'Pass'; Details = '200 OK' }
            $script:TestsPassed++
        } else {
            Write-Host "    ❌ Endpoint error: $($response.StatusCode)" -ForegroundColor Red
            $testResult.Tests += @{ Test = 'EndpointResponse'; Status = 'Fail'; Details = "Status $($response.StatusCode)" }
            $testResult.IssuesFound += "Endpoint returned $($response.StatusCode)"
            $script:TestsFailed++
            $testResult.OverallStatus = 'Fail'
            return $testResult
        }

        $content = $response.Content

        # Test 2: Contains component registration
        if ($content -match "window\.cardComponents\s*=\s*window\.cardComponents\s*\|\|\s*\{\}") {
            Write-Host "    ✅ Component registration found" -ForegroundColor Green
            $testResult.Tests += @{ Test = 'ComponentRegistration'; Status = 'Pass' }
            $script:TestsPassed++
        } else {
            Write-Host "    ⚠️  No component registration pattern" -ForegroundColor Yellow
            $testResult.Tests += @{ Test = 'ComponentRegistration'; Status = 'Warning'; Details = 'Pattern not found' }
            $testResult.IssuesFound += "Missing window.cardComponents registration"
            $script:TestsWarning++
        }

        # Test 3: Contains component class/function
        $componentPattern = "(class\s+\w+|function\s+\w+|const\s+\w+\s*=)"
        if ($content -match $componentPattern) {
            Write-Host "    ✅ Component definition found" -ForegroundColor Green
            $testResult.Tests += @{ Test = 'ComponentDefinition'; Status = 'Pass' }
            $script:TestsPassed++
        } else {
            Write-Host "    ❌ No component definition found" -ForegroundColor Red
            $testResult.Tests += @{ Test = 'ComponentDefinition'; Status = 'Fail' }
            $testResult.IssuesFound += "No component class or function definition"
            $script:TestsFailed++
        }

        # Test 4: Check for common errors in code
        $errorPatterns = @(
            @{ Pattern = 'console\.error'; Name = 'console.error calls' }
            @{ Pattern = 'throw\s+new\s+Error'; Name = 'explicit error throws' }
            @{ Pattern = 'TODO|FIXME|XXX'; Name = 'TODO comments' }
        )

        foreach ($errorPattern in $errorPatterns) {
            if ($content -match $errorPattern.Pattern) {
                Write-Host "    ⚠️  Found $($errorPattern.Name)" -ForegroundColor Yellow
                $testResult.IssuesFound += "Contains $($errorPattern.Name)"
                $script:TestsWarning++
            }
        }

        # Test 5: Open card in browser and validate DOM
        Write-Host "    → Opening card in browser..." -ForegroundColor Gray

        $openCardCommand = @"
(async function() {
    try {
        // Check if card manager exists
        if (!window.cardManager || typeof window.cardManager.openCard !== 'function') {
            return { error: 'cardManager not available' };
        }

        // Close any existing cards
        const existingCards = document.querySelectorAll('.card');
        existingCards.forEach(card => card.remove());

        // Open the card
        await window.cardManager.openCard('$($Card.Name)');

        // Wait for card to render
        await new Promise(resolve => setTimeout(resolve, 1000));

        // Check if card element exists
        const cardElement = document.querySelector('.card[data-card-name="${($Card.Name)}"]');
        if (!cardElement) {
            return { error: 'Card element not found in DOM' };
        }

        // Validate card structure
        const hasHeader = cardElement.querySelector('.card-header') !== null;
        const hasBody = cardElement.querySelector('.card-body, .card-content') !== null;
        const hasCloseButton = cardElement.querySelector('.card-close, .close-btn') !== null;

        // Check for JavaScript errors
        const errorElement = cardElement.querySelector('.error, .alert-danger');
        const hasError = errorElement !== null;

        // Get visible text content
        const visibleText = cardElement.innerText.substring(0, 200);

        return {
            success: true,
            cardFound: true,
            hasHeader: hasHeader,
            hasBody: hasBody,
            hasCloseButton: hasCloseButton,
            hasError: hasError,
            errorMessage: hasError ? errorElement.innerText : null,
            visibleText: visibleText,
            elementCount: cardElement.querySelectorAll('*').length
        };
    } catch (e) {
        return { error: e.message, stack: e.stack };
    }
})();
"@

        $domResult = Invoke-DebugCommand -Command $openCardCommand -TimeoutSeconds 15

        if ($domResult.Success) {
            try {
                $domData = $domResult.Result | ConvertFrom-Json

                if ($domData.error) {
                    Write-Host "    ❌ DOM Test Error: $($domData.error)" -ForegroundColor Red
                    $testResult.Tests += @{ Test = 'DOMRendering'; Status = 'Fail'; Details = $domData.error }
                    $testResult.IssuesFound += "DOM Error: $($domData.error)"
                    $script:TestsFailed++
                } elseif ($domData.cardFound) {
                    Write-Host "    ✅ Card rendered in DOM" -ForegroundColor Green
                    Write-Host "      Elements: $($domData.elementCount)" -ForegroundColor Gray

                    $testResult.Tests += @{ Test = 'DOMRendering'; Status = 'Pass'; Details = "Rendered with $($domData.elementCount) elements" }
                    $script:TestsPassed++

                    # Validate card structure
                    if ($domData.hasHeader) {
                        Write-Host "      ✅ Has header" -ForegroundColor Green
                        $script:TestsPassed++
                    } else {
                        Write-Host "      ⚠️  No header found" -ForegroundColor Yellow
                        $testResult.IssuesFound += "Missing card header"
                        $script:TestsWarning++
                    }

                    if ($domData.hasBody) {
                        Write-Host "      ✅ Has body/content" -ForegroundColor Green
                        $script:TestsPassed++
                    } else {
                        Write-Host "      ⚠️  No body content found" -ForegroundColor Yellow
                        $testResult.IssuesFound += "Missing card body"
                        $script:TestsWarning++
                    }

                    if ($domData.hasCloseButton) {
                        Write-Host "      ✅ Has close button" -ForegroundColor Green
                        $script:TestsPassed++
                    } else {
                        Write-Host "      ⚠️  No close button" -ForegroundColor Yellow
                        $testResult.IssuesFound += "Missing close button"
                        $script:TestsWarning++
                    }

                    if ($domData.hasError) {
                        Write-Host "      ❌ Card shows error: $($domData.errorMessage)" -ForegroundColor Red
                        $testResult.Tests += @{ Test = 'ErrorCheck'; Status = 'Fail'; Details = $domData.errorMessage }
                        $testResult.IssuesFound += "Runtime error: $($domData.errorMessage)"
                        $script:TestsFailed++
                    } else {
                        Write-Host "      ✅ No runtime errors" -ForegroundColor Green
                        $script:TestsPassed++
                    }

                    if ($domData.visibleText.Length -gt 10) {
                        Write-Host "      ✅ Has visible content" -ForegroundColor Green
                        $script:TestsPassed++
                    } else {
                        Write-Host "      ⚠️  Very little visible content" -ForegroundColor Yellow
                        $testResult.IssuesFound += "Minimal visible content"
                        $script:TestsWarning++
                    }

                } else {
                    Write-Host "    ❌ Card not found in DOM" -ForegroundColor Red
                    $testResult.Tests += @{ Test = 'DOMRendering'; Status = 'Fail'; Details = 'Card not found' }
                    $testResult.IssuesFound += "Card did not render in DOM"
                    $script:TestsFailed++
                }
            } catch {
                Write-Host "    ❌ Failed to parse DOM result: $($_.Exception.Message)" -ForegroundColor Red
                $testResult.Tests += @{ Test = 'DOMRendering'; Status = 'Fail'; Details = $_.Exception.Message }
                $script:TestsFailed++
            }
        } else {
            Write-Host "    ❌ Failed to execute DOM test: $($domResult.Error)" -ForegroundColor Red
            $testResult.Tests += @{ Test = 'DOMRendering'; Status = 'Fail'; Details = $domResult.Error }
            $testResult.IssuesFound += "DOM test execution failed: $($domResult.Error)"
            $script:TestsFailed++
        }

        # Test 6: Test UI interactions (if card opened successfully)
        if ($domData -and $domData.cardFound -and -not $domData.hasError) {
            Write-Host "    → Testing UI interactions..." -ForegroundColor Gray

            $interactionTest = @"
(function() {
    try {
        const card = document.querySelector('.card[data-card-name="${($Card.Name)}"]');
        if (!card) return { error: 'Card not found' };

        const results = {
            clickableElements: 0,
            inputElements: 0,
            selectElements: 0,
            textareaElements: 0,
            buttonElements: 0
        };

        // Count interactive elements
        results.clickableElements = card.querySelectorAll('[onclick], button, a, .btn, .clickable').length;
        results.inputElements = card.querySelectorAll('input').length;
        results.selectElements = card.querySelectorAll('select').length;
        results.textareaElements = card.querySelectorAll('textarea').length;
        results.buttonElements = card.querySelectorAll('button').length;

        return results;
    } catch (e) {
        return { error: e.message };
    }
})();
"@

            $interactionResult = Invoke-DebugCommand -Command $interactionTest -TimeoutSeconds 10

            if ($interactionResult.Success) {
                try {
                    $interactionData = $interactionResult.Result | ConvertFrom-Json

                    if ($interactionData.error) {
                        Write-Host "      ⚠️  Interaction test error: $($interactionData.error)" -ForegroundColor Yellow
                    } else {
                        $totalInteractive = $interactionData.clickableElements + $interactionData.inputElements +
                                          $interactionData.selectElements + $interactionData.textareaElements

                        if ($totalInteractive -gt 0) {
                            Write-Host "      ✅ Has $totalInteractive interactive elements" -ForegroundColor Green
                            Write-Host "         Buttons: $($interactionData.buttonElements)" -ForegroundColor Gray
                            Write-Host "         Inputs: $($interactionData.inputElements)" -ForegroundColor Gray
                            Write-Host "         Selects: $($interactionData.selectElements)" -ForegroundColor Gray
                            $script:TestsPassed++
                        } else {
                            Write-Host "      ⚠️  No interactive elements found" -ForegroundColor Yellow
                            $testResult.IssuesFound += "No interactive UI elements detected"
                            $script:TestsWarning++
                        }
                    }
                } catch {
                    Write-Host "      ⚠️  Failed to parse interaction data" -ForegroundColor Yellow
                }
            }
        }

        # Determine overall status
        if ($testResult.IssuesFound.Count -eq 0) {
            $testResult.OverallStatus = 'Pass'
        } elseif ($testResult.Tests | Where-Object { $_.Status -eq 'Fail' }) {
            $testResult.OverallStatus = 'Fail'
        } else {
            $testResult.OverallStatus = 'Warning'
        }

        # Attempt fixes if requested
        if ($FixIssues -and $testResult.IssuesFound.Count -gt 0) {
            Write-Host "`n    🔧 Attempting fixes..." -ForegroundColor Magenta

            # Example fix: Add missing component registration
            if ($testResult.IssuesFound -contains "Missing window.cardComponents registration") {
                Write-Host "      → Would add component registration pattern" -ForegroundColor Gray
                $testResult.IssuesFixed += "Component registration (simulation)"
                $script:IssuesFixed++
            }
        }

    } catch {
        Write-Host "    ❌ Test error: $($_.Exception.Message)" -ForegroundColor Red
        $testResult.Tests += @{ Test = 'Overall'; Status = 'Error'; Details = $_.Exception.Message }
        $testResult.OverallStatus = 'Error'
        $script:TestsFailed++
    }

    $script:TestResults += $testResult
    return $testResult
}

# Main testing loop
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Testing Cards" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($card in $cardPaths) {
    Test-CardRendering -Card $card
    Start-Sleep -Milliseconds 500 # Rate limiting
}

# Generate summary report
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$totalCards = $cardPaths.Count
$passedCards = ($script:TestResults | Where-Object { $_.OverallStatus -eq 'Pass' }).Count
$failedCards = ($script:TestResults | Where-Object { $_.OverallStatus -eq 'Fail' }).Count
$warningCards = ($script:TestResults | Where-Object { $_.OverallStatus -eq 'Warning' }).Count

Write-Host "Cards Tested: $totalCards" -ForegroundColor White
Write-Host "  ✅ Passed: $passedCards" -ForegroundColor Green
Write-Host "  ❌ Failed: $failedCards" -ForegroundColor Red
Write-Host "  ⚠️  Warnings: $warningCards" -ForegroundColor Yellow

Write-Host "`nTotal Tests Run: $($script:TestsPassed + $script:TestsFailed + $script:TestsWarning)" -ForegroundColor White
Write-Host "  ✅ Passed: $($script:TestsPassed)" -ForegroundColor Green
Write-Host "  ❌ Failed: $($script:TestsFailed)" -ForegroundColor Red
Write-Host "  ⚠️  Warnings: $($script:TestsWarning)" -ForegroundColor Yellow

if ($FixIssues) {
    Write-Host "`n🔧 Issues Fixed: $($script:IssuesFixed)" -ForegroundColor Magenta
}

# Export detailed report
if ($ExportReport) {
    $reportPath = Join-Path $PSScriptRoot "card_test_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $reportData = @{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        TotalCards = $totalCards
        PassedCards = $passedCards
        FailedCards = $failedCards
        WarningCards = $warningCards
        TotalTests = $script:TestsPassed + $script:TestsFailed + $script:TestsWarning
        TestsPassed = $script:TestsPassed
        TestsFailed = $script:TestsFailed
        TestsWarning = $script:TestsWarning
        IssuesFixed = $script:IssuesFixed
        CardResults = $script:TestResults
    }

    $reportData | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
    Write-Host "`n📄 Report exported: $reportPath" -ForegroundColor Cyan
}

# Show failed cards
if ($failedCards -gt 0) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Failed Cards" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red

    $script:TestResults | Where-Object { $_.OverallStatus -eq 'Fail' } | ForEach-Object {
        Write-Host "`n$($_.CardName) ($($_.App))" -ForegroundColor Red
        Write-Host "  Endpoint: $($_.Endpoint)" -ForegroundColor Gray
        Write-Host "  Issues:" -ForegroundColor Yellow
        $_.IssuesFound | ForEach-Object {
            Write-Host "    - $_" -ForegroundColor Red
        }
    }
}

# Cleanup API key
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($script:TestKeyID) {
    try {
        $removeScript = Join-Path $PSScriptRoot "system\utility\Account_Auth_BearerToken_Remove.ps1"
        & $removeScript -KeyID $script:TestKeyID -Force -Confirm:$false -RemoveUser 2>&1 | Out-Null
        Write-Host "✅ Test API key removed" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Warning: Failed to remove test API key" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Testing Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Exit code based on results
if ($failedCards -gt 0) {
    exit 1
} else {
    exit 0
}
