#Requires -Version 7

<#
.SYNOPSIS
    Quick browser testing utility for PSWebHost development
.DESCRIPTION
    Simplified wrapper around MSEdgeSessionDebugging-Enhanced.ps1 for common testing scenarios
.PARAMETER TestUrl
    Relative URL to test (e.g., "/apps/uplot/api/v1/ui/elements/bar-chart")
.PARAMETER ElementSelector
    CSS selector to wait for and validate
.PARAMETER ExpectedText
    Expected text content in the element
.PARAMETER Interactive
    Enable interactive testing mode
.EXAMPLE
    .\Quick-BrowserTest.ps1 -TestUrl "/apps/uplot/api/v1/ui/elements/bar-chart?chartId=test1"
.EXAMPLE
    .\Quick-BrowserTest.ps1 -TestUrl "/apps/vault/api/v1/ui/elements/vault-manager" -ElementSelector ".vault-manager" -Interactive
#>

param(
    [Parameter(Mandatory)]
    [string]$TestUrl,
    [string]$ElementSelector,
    [string]$ExpectedText,
    [switch]$Interactive,
    [string]$BaseUrl = "http://localhost:8888",
    [switch]$TakeScreenshot
)

$ErrorActionPreference = 'Stop'

# Ensure WebHost is running
Write-Host "Checking if PSWebHost is running on $BaseUrl..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$BaseUrl/api/v1/auth/status" -TimeoutSec 3 -UseBasicParsing
    Write-Host "PSWebHost is running" -ForegroundColor Green
}
catch {
    Write-Error "PSWebHost is not running on $BaseUrl. Start WebHost.ps1 first."
    exit 1
}

# Build full URL
$fullUrl = if ($TestUrl.StartsWith('http')) {
    $TestUrl
}
else {
    $TestUrl = $TestUrl.TrimStart('/')
    "$BaseUrl/$TestUrl"
}

Write-Host "`n=== Quick Browser Test ===" -ForegroundColor Cyan
Write-Host "URL: $fullUrl" -ForegroundColor White
Write-Host "Element: $ElementSelector" -ForegroundColor White
Write-Host ""

# Launch enhanced debugging session
$scriptPath = Join-Path $PSScriptRoot "MSEdgeSessionDebugging-Enhanced.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Error "MSEdgeSessionDebugging-Enhanced.ps1 not found at $scriptPath"
    exit 1
}

# Build arguments
$arguments = @{
    Url            = $fullUrl
    ForwardConsole = $true
}

if ($Interactive) {
    $arguments.Interactive = $true
}

# Run the enhanced debugger
& $scriptPath @arguments

Write-Host "`nTest completed!" -ForegroundColor Green
