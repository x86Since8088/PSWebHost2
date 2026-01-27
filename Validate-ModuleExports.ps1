#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates module manifests match actual function definitions
.DESCRIPTION
    Checks that FunctionsToExport in .psd1 files match actual functions in .psm1 files
#>

Write-Host "`n=== Module Export Validation ===" -ForegroundColor Cyan

$modulesPath = "C:\SC\PsWebHost\modules"
$manifests = Get-ChildItem $modulesPath -Recurse -Filter *.psd1

$issues = @()
$validated = 0

foreach ($manifest in $manifests) {
    $moduleName = $manifest.BaseName
    Write-Host "`nValidating: $moduleName" -ForegroundColor Yellow

    # Find corresponding .psm1 file
    $psm1File = Join-Path $manifest.DirectoryName "$moduleName.psm1"

    if (-not (Test-Path $psm1File)) {
        Write-Host "  ⚠ No .psm1 file found" -ForegroundColor Yellow
        continue
    }

    # Read manifest
    try {
        $manifestData = Import-PowerShellDataFile -Path $manifest.FullName
    } catch {
        Write-Host "  ✗ Failed to parse manifest: $_" -ForegroundColor Red
        $issues += @{
            Module = $moduleName
            Issue = "Manifest parse error: $_"
        }
        continue
    }

    # Get exported functions from manifest
    $exportedFunctions = $manifestData.FunctionsToExport
    if ($null -eq $exportedFunctions -or $exportedFunctions.Count -eq 0) {
        Write-Host "  - No functions exported (FunctionsToExport is empty)" -ForegroundColor Gray
        continue
    }

    # Get actual functions from .psm1
    $psm1Content = Get-Content $psm1File -Raw
    $functionPattern = 'function\s+([a-zA-Z0-9_-]+)\s*\{'
    $actualFunctions = [regex]::Matches($psm1Content, $functionPattern) | ForEach-Object {
        $_.Groups[1].Value
    }

    Write-Host "  Exported: $($exportedFunctions.Count) functions" -ForegroundColor Gray
    Write-Host "  Defined:  $($actualFunctions.Count) functions" -ForegroundColor Gray

    # Check for mismatches
    $missingInPsm1 = @()
    $missingInExports = @()

    # Check each exported function exists in .psm1
    foreach ($exportedFunc in $exportedFunctions) {
        if ($actualFunctions -notcontains $exportedFunc) {
            $missingInPsm1 += $exportedFunc
        }
    }

    # Check each .psm1 function is exported (only for public functions, not helpers)
    foreach ($actualFunc in $actualFunctions) {
        # Skip private/helper functions (usually start with _ or are lowercase)
        if ($actualFunc -match '^[A-Z]' -and $actualFunc -notmatch '^_') {
            if ($exportedFunctions -notcontains $actualFunc) {
                $missingInExports += $actualFunc
            }
        }
    }

    # Report issues
    if ($missingInPsm1.Count -gt 0) {
        Write-Host "  ✗ Functions exported but not defined in .psm1:" -ForegroundColor Red
        $missingInPsm1 | ForEach-Object {
            Write-Host "    - $_" -ForegroundColor Red
        }
        $issues += @{
            Module = $moduleName
            Issue = "Exported but not defined: $($missingInPsm1 -join ', ')"
        }
    }

    if ($missingInExports.Count -gt 0) {
        Write-Host "  ⚠ Functions defined but not exported:" -ForegroundColor Yellow
        $missingInExports | ForEach-Object {
            Write-Host "    - $_" -ForegroundColor Yellow
        }
        # This is a warning, not an error (some functions may be intentionally private)
    }

    if ($missingInPsm1.Count -eq 0 -and $missingInExports.Count -eq 0) {
        Write-Host "  ✓ All exports valid" -ForegroundColor Green
        $validated++
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Modules validated: $validated" -ForegroundColor Green
Write-Host "Modules with issues: $($issues.Count)" -ForegroundColor $(if ($issues.Count -eq 0) { "Green" } else { "Red" })

if ($issues.Count -gt 0) {
    Write-Host "`n=== Issues Found ===" -ForegroundColor Red
    $issues | ForEach-Object {
        Write-Host "  $($_.Module): $($_.Issue)" -ForegroundColor Red
    }
    Write-Host "`nThese issues will cause 'term not recognized' errors in runspaces!" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n✓ All module exports are valid" -ForegroundColor Green
    exit 0
}
