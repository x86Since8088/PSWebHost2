#Requires -Version 7

<#
.SYNOPSIS
    Twin Test Template for PSWebHost Apps
.DESCRIPTION
    Template for creating comprehensive twin tests that validate:
    - CLI functionality (PowerShell backend logic)
    - Browser functionality (JavaScript frontend components)
    - API endpoints (integration tests)
    - Data integrity (database operations)

.PARAMETER TestMode
    Test mode: CLI, Browser, Integration, All
.PARAMETER AppName
    Name of the app being tested
.PARAMETER BaseUrl
    Base URL of PSWebHost instance (default: http://localhost:8888)

.EXAMPLE
    .\AppName.Tests.ps1 -TestMode All
    Run all tests for the app

.EXAMPLE
    .\AppName.Tests.ps1 -TestMode CLI
    Run only CLI/backend tests
#>

param(
    [ValidateSet('CLI', 'Browser', 'Integration', 'All')]
    [string]$TestMode = 'All',

    [string]$AppName = 'SQLiteManager',

    [string]$BaseUrl = 'http://localhost:8888'
)

# Import Pester if available
if (Get-Module -ListAvailable -Name Pester) {
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction SilentlyContinue
    $UsePester = $true
} else {
    Write-Warning "Pester module not found. Using basic test framework."
    $UsePester = $false
}

# Test results tracking
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

#region Helper Functions

function Test-Assert {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$Message
    )

    $result = [PSCustomObject]@{
        TestName = $TestName
        Status = if ($Condition) { 'Passed' } else { 'Failed' }
        Message = $Message
        Timestamp = Get-Date -Format 'o'
    }

    $script:TestResults.Tests += $result

    if ($Condition) {
        $script:TestResults.Passed++
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
    } else {
        $script:TestResults.Failed++
        Write-Host "  [FAIL] $TestName : $Message" -ForegroundColor Red
    }
}

function Invoke-ApiTest {
    param(
        [string]$TestName,
        [string]$Endpoint,
        [string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [object]$Body,
        [int]$ExpectedStatusCode = 200
    )

    try {
        $uri = "$BaseUrl$Endpoint"
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $Headers
            ErrorAction = 'Stop'
        }

        if ($Body) {
            $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
            $params['ContentType'] = 'application/json'
        }

        $response = Invoke-WebRequest @params

        Test-Assert -TestName $TestName `
            -Condition ($response.StatusCode -eq $ExpectedStatusCode) `
            -Message "Expected status $ExpectedStatusCode, got $($response.StatusCode)"

        return $response

    } catch {
        Test-Assert -TestName $TestName `
            -Condition $false `
            -Message "API call failed: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region CLI Tests

function Test-CLIFunctionality {
    Write-Host "`n=== CLI Tests ===" -ForegroundColor Cyan

    # Example: Test module import
    Test-Assert -TestName "Module Import" `
        -Condition (Get-Module -Name "PSWebSQLiteManager" -ErrorAction SilentlyContinue) `
        -Message "Module should be loaded"

    # Example: Test function availability
    Test-Assert -TestName "Function Exists" `
        -Condition (Get-Command -Name "Get-SQLiteManager" -ErrorAction SilentlyContinue) `
        -Message "Function should be available"

    # Example: Test function output
    $result = Get-SQLiteManager -Parameter "test"
    Test-Assert -TestName "Function Returns Expected Output" `
        -Condition ($result -eq "expected") `
        -Message "Function should return expected value"

    # Add more CLI tests here...
}

#endregion

#region Browser Tests

function Test-BrowserFunctionality {
    Write-Host "`n=== Browser Tests ===" -ForegroundColor Cyan

    # Note: Browser tests are typically run via the UnitTests app
    # This function prepares test metadata

    Write-Host "  Browser tests should be run via UnitTests app:" -ForegroundColor Yellow
    Write-Host "  http://localhost:8888/apps/unittests/api/v1/ui/elements/unit-test-runner" -ForegroundColor Gray

    # You can validate that test files exist
    $testSuiteFile = Join-Path $PSScriptRoot "browser-tests.js"

    Test-Assert -TestName "Browser Test Suite Exists" `
        -Condition (Test-Path $testSuiteFile) `
        -Message "Browser test suite file should exist at $testSuiteFile"
}

#endregion

#region Integration Tests

function Test-IntegrationFunctionality {
    Write-Host "`n=== Integration Tests ===" -ForegroundColor Cyan

    # Test app status endpoint
    Invoke-ApiTest -TestName "App Status Endpoint" `
        -Endpoint "/apps/$(sqlitemanager)/api/v1/status" `
        -ExpectedStatusCode 200

    # Test UI element endpoint
    Invoke-ApiTest -TestName "Home UI Element" `
        -Endpoint "/apps/$(sqlitemanager)/api/v1/ui/elements/$(sqlitemanager)-home" `
        -ExpectedStatusCode 200

    # Add more integration tests here...

    # Example: Test data endpoint
    # Invoke-ApiTest -TestName "Data Endpoint" `
    #     -Endpoint "/apps/$(sqlitemanager)/api/v1/data" `
    #     -Method 'POST' `
    #     -Body @{ query = "test" } `
    #     -ExpectedStatusCode 200
}

#endregion

#region Main Execution

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Twin Tests: $AppName" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Test Mode: $TestMode" -ForegroundColor Gray
Write-Host "Base URL: $BaseUrl" -ForegroundColor Gray
Write-Host ""

# Run tests based on mode
if ($TestMode -in @('CLI', 'All')) {
    Test-CLIFunctionality
}

if ($TestMode -in @('Browser', 'All')) {
    Test-BrowserFunctionality
}

if ($TestMode -in @('Integration', 'All')) {
    Test-IntegrationFunctionality
}

# Generate summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host "Total:   $($script:TestResults.Tests.Count)" -ForegroundColor White
Write-Host ""

# Save results
$resultsPath = Join-Path $PSScriptRoot "test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$script:TestResults | ConvertTo-Json -Depth 10 | Out-File $resultsPath -Encoding UTF8
Write-Host "Results saved: $resultsPath" -ForegroundColor Gray
Write-Host ""

# Return exit code
if ($script:TestResults.Failed -gt 0) {
    Write-Host "Tests FAILED!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests PASSED!" -ForegroundColor Green
    exit 0
}

#endregion

