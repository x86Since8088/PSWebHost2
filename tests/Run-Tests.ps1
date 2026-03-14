#Requires -Version 7
<#
.SYNOPSIS
    Test runner helper - runs tests from tests directory
.DESCRIPTION
    Provides easy access to test scripts organized in subdirectories
.EXAMPLE
    .\Run-Tests.ps1 -Category auth
    .\Run-Tests.ps1 -Name test_auth_quick
#>
param(
    [ValidateSet('auth', 'cards', 'debug', 'metrics', 'memory', 'modules', 'integration', 'utilities', 'all')]
    [string]$Category = 'all',
    [string]$Name,
    [switch]$List
)

$testsRoot = $PSScriptRoot
$projectRoot = Split-Path $testsRoot -Parent

# Add project root to path for module access
if ($env:PSModulePath -notlike "*$projectRoot\modules*") {
    $env:PSModulePath = "$projectRoot\modules;$env:PSModulePath"
}

if ($List) {
    Write-Host "`n=== Available Test Categories ===" -ForegroundColor Cyan
    Get-ChildItem -Path $testsRoot -Directory |
        Where-Object { $_.Name -notin @('deprecated', 'helpers', 'pester', 'test-code', 'test-host-logs', 'twin') } |
        ForEach-Object {
            $count = (Get-ChildItem -Path $_.FullName -Filter "*.ps1" -File).Count
            Write-Host "  $($_.Name): $count tests"
        }
    return
}

if ($Name) {
    $script = Get-ChildItem -Path $testsRoot -Filter "$Name*.ps1" -Recurse -File | Select-Object -First 1
    if ($script) {
        Write-Host "Running: $($script.Name)" -ForegroundColor Yellow
        & $script.FullName
    } else {
        Write-Host "Test not found: $Name" -ForegroundColor Red
    }
    return
}

if ($Category -eq 'all') {
    $categories = @('auth', 'cards', 'debug', 'metrics', 'memory', 'modules', 'integration', 'utilities')
} else {
    $categories = @($Category)
}

foreach ($cat in $categories) {
    $catPath = Join-Path $testsRoot $cat
    if (Test-Path $catPath) {
        Write-Host "`n=== Running $cat tests ===" -ForegroundColor Cyan
        Get-ChildItem -Path $catPath -Filter "*.ps1" -File | ForEach-Object {
            Write-Host "  $($_.Name)..." -ForegroundColor Gray
        }
    }
}

Write-Host "`nUse -Name <test_name> to run a specific test, or -List to see all categories."
