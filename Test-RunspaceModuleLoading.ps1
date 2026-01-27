#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests module loading in async runspaces
.DESCRIPTION
    Verifies that modules are correctly loaded in the async runspace pool
#>

Write-Host "`n=== Runspace Module Loading Diagnostics ===" -ForegroundColor Cyan

# Check if server is running
if ($null -eq $global:AsyncRunspacePool -or -not $global:AsyncRunspacePool.Initialized) {
    Write-Host "✗ Async runspace pool is not initialized" -ForegroundColor Red
    Write-Host "  Server must be running to test runspaces" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Async runspace pool is initialized" -ForegroundColor Green
Write-Host "  Runspace count: $($global:AsyncRunspacePool.Runspaces.Count)" -ForegroundColor Gray

# Test a runspace
$testRunspace = $global:AsyncRunspacePool.Runspaces[0]
if (-not $testRunspace) {
    Write-Host "✗ No runspaces available" -ForegroundColor Red
    exit 1
}

Write-Host "`nTesting runspace 0 (ID: $($testRunspace.Runspace.InstanceId))" -ForegroundColor Yellow

# Create a test script to check module availability
$testScript = {
    $result = @{
        LoadedModules = @()
        AvailableFunctions = @()
        ContextResponseAvailable = $false
        PSWebServerAvailable = $false
    }

    # Get loaded modules
    $modules = Get-Module
    $result.LoadedModules = $modules.Name

    # Check for specific functions
    $result.AvailableFunctions = (Get-Command -CommandType Function).Name

    # Check if context_response is available
    $result.ContextResponseAvailable = $null -ne (Get-Command -Name 'context_response' -ErrorAction SilentlyContinue)

    # Check if global variables are available
    $result.PSWebServerAvailable = $null -ne $global:PSWebServer

    return $result
}

# Execute test in the runspace
$ps = [powershell]::Create()
$ps.Runspace = $testRunspace.Runspace
[void]$ps.AddScript($testScript)

try {
    $result = $ps.Invoke()

    Write-Host "`n--- Loaded Modules ---" -ForegroundColor Cyan
    if ($result.LoadedModules.Count -eq 0) {
        Write-Host "  ✗ No modules loaded" -ForegroundColor Red
    } else {
        $result.LoadedModules | ForEach-Object {
            if ($_ -like "PSWebHost*" -or $_ -eq "PSWebSQLite") {
                Write-Host "  ✓ $_" -ForegroundColor Green
            } else {
                Write-Host "  - $_" -ForegroundColor Gray
            }
        }
    }

    Write-Host "`n--- Critical Functions ---" -ForegroundColor Cyan

    $criticalFunctions = @(
        'context_response',
        'Process-HttpRequest',
        'Get-RequestBody',
        'Write-PSWebHostLog',
        'Get-PSWebSQLiteData'
    )

    foreach ($funcName in $criticalFunctions) {
        $available = $result.AvailableFunctions -contains $funcName
        if ($available) {
            Write-Host "  ✓ $funcName" -ForegroundColor Green
        } else {
            Write-Host "  ✗ $funcName" -ForegroundColor Red
        }
    }

    Write-Host "`n--- Global Variables ---" -ForegroundColor Cyan
    if ($result.PSWebServerAvailable) {
        Write-Host "  ✓ `$global:PSWebServer" -ForegroundColor Green
    } else {
        Write-Host "  ✗ `$global:PSWebServer" -ForegroundColor Red
    }

    # Check for common issues
    Write-Host "`n--- Analysis ---" -ForegroundColor Cyan

    if (-not $result.ContextResponseAvailable) {
        Write-Host "  ⚠ context_response function not available" -ForegroundColor Red
        Write-Host "    This will cause 'term not recognized' errors" -ForegroundColor Yellow
        Write-Host "    Fix: Restart server to reload PSWebHost_Support module" -ForegroundColor Yellow
    }

    if ($result.LoadedModules -notcontains 'PSWebHost_Support') {
        Write-Host "  ⚠ PSWebHost_Support module not loaded" -ForegroundColor Red
        Write-Host "    This module contains critical functions" -ForegroundColor Yellow
    }

    if (-not $result.PSWebServerAvailable) {
        Write-Host "  ⚠ `$global:PSWebServer not available" -ForegroundColor Red
        Write-Host "    This will cause app initialization failures" -ForegroundColor Yellow
    }

    if ($result.ContextResponseAvailable -and
        $result.LoadedModules -contains 'PSWebHost_Support' -and
        $result.PSWebServerAvailable) {
        Write-Host "  ✓ All critical components available" -ForegroundColor Green
    }

} catch {
    Write-Host "✗ Failed to test runspace: $_" -ForegroundColor Red
} finally {
    $ps.Dispose()
}

Write-Host "`n=== Recommendations ===" -ForegroundColor Cyan
Write-Host "1. If context_response is missing: Restart server to reload fixed module"
Write-Host "2. If modules are missing: Check system/init.ps1 for errors"
Write-Host "3. If global variables are missing: Check AsyncRunspacePool.ps1 setup script"
Write-Host ""
