<#
.SYNOPSIS
    Test script for WebhostRealtimeEvents API endpoints
.DESCRIPTION
    Demonstrates how to test API endpoints using the -Test switch and roles parameter
.EXAMPLE
    .\Test-Endpoints.ps1
    Tests all endpoints with default authenticated role
.EXAMPLE
    .\Test-Endpoints.ps1 -Endpoint status
    Tests only the status endpoint
.EXAMPLE
    .\Test-Endpoints.ps1 -Endpoint logs -Roles @('authenticated', 'admin')
    Tests the logs endpoint with specific roles
#>

param(
    [ValidateSet('all', 'status', 'logs')]
    [string]$Endpoint = 'all',

    [string[]]$Roles = @('authenticated')
)

$ErrorActionPreference = 'Stop'

# Get the app routes directory
$appRoot = Split-Path $PSScriptRoot -Parent
$routesRoot = Join-Path $appRoot 'routes\api\v1'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "WebhostRealtimeEvents API Endpoint Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Test Status Endpoint
if ($Endpoint -eq 'all' -or $Endpoint -eq 'status') {
    Write-Host "`n--- Testing Status Endpoint ---" -ForegroundColor Magenta
    $statusScript = Join-Path $routesRoot 'status\get.ps1'

    if (Test-Path $statusScript) {
        & $statusScript -Test -roles $Roles
    } else {
        Write-Host "Status endpoint not found: $statusScript" -ForegroundColor Red
    }
}

# Test Logs Endpoint
if ($Endpoint -eq 'all' -or $Endpoint -eq 'logs') {
    Write-Host "`n--- Testing Logs Endpoint (default parameters) ---" -ForegroundColor Magenta
    $logsScript = Join-Path $routesRoot 'logs\get.ps1'

    if (Test-Path $logsScript) {
        & $logsScript -Test -roles $Roles
    } else {
        Write-Host "Logs endpoint not found: $logsScript" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Tests Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "You can also test via URL with query parameters:" -ForegroundColor Yellow
Write-Host "  /apps/WebhostRealtimeEvents/api/v1/status?test=true&roles=authenticated" -ForegroundColor Gray
Write-Host "  /apps/WebhostRealtimeEvents/api/v1/logs?test=true&roles=authenticated&timeRange=30" -ForegroundColor Gray
