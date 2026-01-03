# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

<#
.SYNOPSIS
    Runs all tests in the twin test structure

.DESCRIPTION
    This script runs all Pester tests in the tests/twin directory, which mirrors
    the main project structure. Tests are organized by component type (routes,
    system, modules, public).

.PARAMETER Path
    Specific path to test. Defaults to all twin tests.

.PARAMETER Tag
    Filter tests by tag

.PARAMETER ExcludeTag
    Exclude tests by tag

.PARAMETER Output
    Output level: None, Minimal, Normal, Detailed, Diagnostic
    Default: Detailed

.PARAMETER CodeCoverage
    Enable code coverage analysis

.EXAMPLE
    .\Run-AllTwinTests.ps1
    Runs all twin tests with detailed output

.EXAMPLE
    .\Run-AllTwinTests.ps1 -Path routes
    Runs only route tests

.EXAMPLE
    .\Run-AllTwinTests.ps1 -CodeCoverage
    Runs all tests with code coverage analysis

.EXAMPLE
    .\Run-AllTwinTests.ps1 -Tag "Authentication" -Output Normal
    Runs only tests tagged with "Authentication"
#>

param(
    [string]$Path = $PSScriptRoot,
    [string[]]$Tag,
    [string[]]$ExcludeTag,
    [ValidateSet('None', 'Minimal', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',
    [switch]$CodeCoverage
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost Twin Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Ensure Pester module is available
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "ERROR: Pester module not found. Installing..." -ForegroundColor Red
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import Pester
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

# Create Pester configuration
$config = New-PesterConfiguration

# Set paths
$config.Run.Path = $Path
$config.Run.PassThru = $true

# Set output
$config.Output.Verbosity = $Output

# Set tags if provided
if ($Tag) {
    $config.Filter.Tag = $Tag
}
if ($ExcludeTag) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

# Configure code coverage if requested
if ($CodeCoverage) {
    Write-Host "Code coverage enabled`n" -ForegroundColor Yellow
    $config.CodeCoverage.Enabled = $true

    # Set paths to analyze for coverage
    $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
    $config.CodeCoverage.Path = @(
        (Join-Path $ProjectRoot 'routes'),
        (Join-Path $ProjectRoot 'system'),
        (Join-Path $ProjectRoot 'modules')
    )

    $config.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'coverage.xml'
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

# Run tests
$result = Invoke-Pester -Configuration $config

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total:  " -NoNewline
Write-Host $result.TotalCount -ForegroundColor White
Write-Host "Passed: " -NoNewline
Write-Host $result.PassedCount -ForegroundColor Green
Write-Host "Failed: " -NoNewline
Write-Host $result.FailedCount -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped:" -NoNewline
Write-Host $result.SkippedCount -ForegroundColor Yellow

if ($result.Duration) {
    Write-Host "Duration: $($result.Duration.TotalSeconds) seconds`n" -ForegroundColor Gray
}

# Code coverage summary
if ($CodeCoverage -and $result.CodeCoverage) {
    Write-Host "`nCode Coverage:" -ForegroundColor Cyan
    $coverage = $result.CodeCoverage
    $coveragePercent = if ($coverage.CommandsAnalyzedCount -gt 0) {
        [math]::Round(($coverage.CommandsExecutedCount / $coverage.CommandsAnalyzedCount) * 100, 2)
    } else { 0 }

    Write-Host "  Analyzed: $($coverage.CommandsAnalyzedCount) commands"
    Write-Host "  Executed: $($coverage.CommandsExecutedCount) commands"
    Write-Host "  Coverage: " -NoNewline
    $coverageColor = if ($coveragePercent -ge 80) { 'Green' } elseif ($coveragePercent -ge 60) { 'Yellow' } else { 'Red' }
    Write-Host "$coveragePercent%" -ForegroundColor $coverageColor
    Write-Host "  Report saved to: $($config.CodeCoverage.OutputPath)`n"
}

# Exit with appropriate code
if ($result.FailedCount -gt 0) {
    Write-Host "Tests FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
